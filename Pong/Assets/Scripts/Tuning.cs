namespace Pong;

static class Tuning
{
    public const float PaddleSpeed = 10.0f;
    public const float PaddleX = 5.0f;
    public const float PaddleHalfHeight = 1.0f;
    // how far the AI lets the ball drift from its paddle's centre before it moves
    public const float AiDeadZone = 0.15f;

    public const float BallSpeed = 9.0f;
    public const float BallRadius = 0.25f;
    public const float MaxBounceAngle = 60.0f * float.Pi / 180.0f;
    // a ball this slow across the table would bounce between the walls forever
    public const float MinBallSpeedX = 1.5f;

    public const float WallY = 5.0f;
    public const float WallHalfThickness = 0.2f;
    public const float PaddleLimitY = WallY - WallHalfThickness - PaddleHalfHeight;
    public const float GoalX = 6.0f;
    public const float ServeDelay = 2.0f;

    public const uint ConnectTimeoutMs = 5000;
    public const float SendInterval = 1.0f / 30.0f;
    // a pair of paddle reports plays back over a little more than the send interval, so ordinary jitter lands the next
    // one before the segment runs out
    public const float PaddleInterpolationWindow = SendInterval * 1.25f;
    // how hard a remote paddle chases its interpolated target, per second, and how much faster than a local one it may
    // go doing it, so a late packet doesn't turn the catch up into a dash
    public const float PaddleFollowGain = 12.0f;
    public const float PaddleFollowSpeedScale = 2.0f;
    // how hard the guest steers its ball back onto the host's, and the error past which it gives up and teleports
    public const float BallCorrectionGain = 10.0f;
    public const float BallSnapDistance = 1.5f;
}
