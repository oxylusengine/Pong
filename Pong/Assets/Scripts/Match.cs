using System;
using System.Numerics;

using Oxylus;

namespace Pong;

// player one plays the right paddle, player two the left one
static class Players
{
    public const int One = 0;
    public const int Two = 1;
}

enum PaddleControl
{
    ArrowKeys,
    WsKeys,
    // the one paddle this machine plays online, either key set moves it
    AnyKeys,
    Ai,
    // the online opponent's, which follows their reports
    Remote,
}

// the paddles, the ball and the score. Only the authority, the one machine that plays offline or hosts online, decides
// goals and bounces, a guest is told about them
sealed class Match : IDisposable
{
    readonly Entity[] paddles;
    readonly PaddleControl[] controls;
    readonly Entity ball;
    readonly bool isAuthority;
    readonly RemotePaddle? remote;
    readonly int[] scores = [0, 0];
    // everything spawned, for Dispose
    readonly Entity[] entities;
    float serveTimer;
    float serveDirection = 1.0f;

    // the authority's, so it can tell the guest
    public event Action? PointScored;
    public event Action? Served;

    public Match(World world, PaddleControl one, PaddleControl two, bool isAuthority, RemotePaddle? remote = null)
    {
        var topWall = Arena.SpawnWall(world, "top_wall", Tuning.WallY);
        var bottomWall = Arena.SpawnWall(world, "bottom_wall", -Tuning.WallY);
        paddles = [Arena.SpawnPaddle(world, "player_one", Tuning.PaddleX), Arena.SpawnPaddle(world, "player_two", -Tuning.PaddleX)];
        controls = [one, two];
        ball = Arena.SpawnBall(world);
        entities = [topWall, bottomWall, .. paddles, ball];
        this.isAuthority = isAuthority;
        this.remote = remote;
        if (isAuthority)
        {
            Serve();
        }
    }

    public int ScoreOne => scores[Players.One];
    public int ScoreTwo => scores[Players.Two];
    public int LastScorer { get; private set; } = -1;
    public bool IsServing => serveTimer > 0.0f;
    public int Countdown => (int)MathF.Ceiling(serveTimer);
    public Vector2 BallPosition => Flat(ball.Body.Position);
    public Vector2 BallVelocity => Flat(ball.Body.LinearVelocity);

    public float PaddleY(int player) => paddles[player].Body.Position.Y;

    public void Update(float deltaTime, bool isInputFocused)
    {
        for (var player = 0; player < paddles.Length; player++)
        {
            MovePaddle(player, deltaTime, isInputFocused);
        }

        if (IsServing)
        {
            serveTimer -= deltaTime;
            if (!IsServing && isAuthority)
            {
                Serve();
            }

            return;
        }

        if (!isAuthority)
        {
            return;
        }

        var x = ball.Body.Position.X;
        if (x > Tuning.GoalX)
        {
            Score(Players.Two);
        }
        else if (x < -Tuning.GoalX)
        {
            Score(Players.One);
        }
        else
        {
            KeepBallCrossing();
        }
    }

    // the angle a paddle sends the ball off at follows where it was hit, the centre straight back and the edges steep
    public void OnContact(in Contact contact)
    {
        if (!isAuthority || contact.Event != ContactEvent.Added)
        {
            return;
        }

        var paddle = contact.Self == ball ? contact.Other : contact.Other == ball ? contact.Self : default;
        if (paddle != paddles[Players.One] && paddle != paddles[Players.Two])
        {
            return;
        }

        var paddlePosition = paddle.Body.Position;
        var offset = Math.Clamp((ball.Body.Position.Y - paddlePosition.Y) / Tuning.PaddleHalfHeight, -1.0f, 1.0f);
        var angle = offset * Tuning.MaxBounceAngle;
        var direction = paddlePosition.X < 0.0f ? 1.0f : -1.0f;
        ball.Body.SetLinearVelocity(new Vector3(direction * MathF.Cos(angle), MathF.Sin(angle), 0.0f) * Tuning.BallSpeed);
    }

    // the guest's side of the authority's PointScored and Served
    public void ApplyScore(int one, int two, int scorer)
    {
        scores[Players.One] = one;
        scores[Players.Two] = two;
        LastScorer = scorer;
        serveTimer = Tuning.ServeDelay;
    }

    public void Resume() => serveTimer = 0.0f;

    // the guest's ball runs its own physics between the host's updates, which nudge it back onto the host's path
    public void CorrectBall(Vector2 position, Vector2 velocity)
    {
        var body = ball.Body;
        var error = position - Flat(body.Position);
        if (error.LengthSquared() > Tuning.BallSnapDistance * Tuning.BallSnapDistance)
        {
            body.SetPosition(new Vector3(position, 0.0f));
            body.SetLinearVelocity(new Vector3(velocity, 0.0f));
            return;
        }

        body.SetLinearVelocity(new Vector3(velocity + error * Tuning.BallCorrectionGain, 0.0f));
    }

    public void Dispose()
    {
        foreach (var entity in entities)
        {
            entity.Destruct();
        }
    }

    void MovePaddle(int player, float deltaTime, bool isInputFocused)
    {
        var body = paddles[player].Body;
        var y = body.Position.Y;
        var velocity = controls[player] switch
        {
            PaddleControl.ArrowKeys => Keys(ScanCode.Up, ScanCode.Down, isInputFocused) * Tuning.PaddleSpeed,
            PaddleControl.WsKeys => Keys(ScanCode.W, ScanCode.S, isInputFocused) * Tuning.PaddleSpeed,
            PaddleControl.AnyKeys => Math.Clamp(
                Keys(ScanCode.Up, ScanCode.Down, isInputFocused) + Keys(ScanCode.W, ScanCode.S, isInputFocused), -1.0f, 1.0f)
                * Tuning.PaddleSpeed,
            PaddleControl.Ai => Chase(ball.Body.Position.Y - y),
            PaddleControl.Remote => Follow(y),
            _ => 0.0f,
        };

        // stopped at the walls, which a kinematic body would pass straight through
        if (deltaTime > 0.0f)
        {
            velocity = Math.Clamp(velocity, (-Tuning.PaddleLimitY - y) / deltaTime, (Tuning.PaddleLimitY - y) / deltaTime);
        }

        body.SetLinearVelocity(new Vector3(0.0f, velocity, 0.0f));
    }

    static float Keys(ScanCode up, ScanCode down, bool isInputFocused)
    {
        if (!isInputFocused)
        {
            return 0.0f;
        }

        return (Input.IsKeyHeld(up) ? 1.0f : 0.0f) - (Input.IsKeyHeld(down) ? 1.0f : 0.0f);
    }

    static float Chase(float distance) =>
        MathF.Abs(distance) > Tuning.AiDeadZone ? MathF.Sign(distance) * Tuning.PaddleSpeed : 0.0f;

    float Follow(float y)
    {
        if (remote is null || !remote.TrySample(out var targetY, out var targetVelocity))
        {
            return 0.0f;
        }

        var maxSpeed = Tuning.PaddleSpeed * Tuning.PaddleFollowSpeedScale;
        return Math.Clamp(targetVelocity + (targetY - y) * Tuning.PaddleFollowGain, -maxSpeed, maxSpeed);
    }

    void Score(int scorer)
    {
        scores[scorer]++;
        LastScorer = scorer;
        // the next serve goes to whoever conceded
        serveDirection = scorer == Players.Two ? 1.0f : -1.0f;
        serveTimer = Tuning.ServeDelay;
        ball.Body.SetPosition(Vector3.Zero);
        ball.Body.SetLinearVelocity(Vector3.Zero);
        Log.Info($"Player {scorer + 1} scored, {ScoreOne} to {ScoreTwo}");
        PointScored?.Invoke();
    }

    void Serve()
    {
        ball.Body.SetLinearVelocity(new Vector3(serveDirection * Tuning.BallSpeed, 0.0f, 0.0f));
        Served?.Invoke();
    }

    // wall bounces never change the ball's horizontal speed, only a stuck simulation can leave it crawling between them
    void KeepBallCrossing()
    {
        var velocity = ball.Body.LinearVelocity;
        if (MathF.Abs(velocity.X) >= Tuning.MinBallSpeedX)
        {
            return;
        }

        var x = ball.Body.Position.X;
        ball.Body.SetLinearVelocity(velocity with { X = x > 0.0f ? -Tuning.MinBallSpeedX : Tuning.MinBallSpeedX });
    }

    static Vector2 Flat(Vector3 value) => new(value.X, value.Y);
}
