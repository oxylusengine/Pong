using System;
using System.Numerics;

using Oxylus;

namespace Pong;

// one online game: the host plays player one and runs the simulation, the guest plays player two and follows it
sealed class NetSession : IDisposable
{
    // host to guest, both players' ready flags
    static readonly Rpc<bool, bool> LobbyRpc = new("lobby");
    // guest to host
    static readonly Rpc<bool> ReadyRpc = new("ready");
    static readonly Rpc StartRpc = new("start");
    // both ways, the sender's paddle
    static readonly Rpc<float> PaddleRpc = new("paddle");
    // host to guest, the ball's position and velocity
    static readonly Rpc<float, float, float, float> BallRpc = new("ball");
    // host to guest, player one's and two's scores and who scored
    static readonly Rpc<int, int, int> ScoreRpc = new("score");
    static readonly Rpc ServeRpc = new("serve");

    readonly NetServer? server;
    readonly NetClient? client;
    NetClientId? guest;
    float sendTimer;

    public event Action? PeerConnected;
    public event Action<string>? Ended;
    public event Action? LobbyChanged;
    public event Action? MatchStarted;
    public event Action<Vector2, Vector2>? BallReceived;
    public event Action<int, int, int>? ScoreReceived;
    public event Action? ServeReceived;

    NetSession(NetServer? server, NetClient? client)
    {
        this.server = server;
        this.client = client;
    }

    public bool IsHost => server is not null;
    public int LocalPlayer => IsHost ? Players.One : Players.Two;
    public bool IsPeerConnected { get; private set; }
    public bool IsHostReady { get; private set; }
    public bool IsGuestReady { get; private set; }
    public bool IsLocalReady => IsHost ? IsHostReady : IsGuestReady;
    public bool CanStart => IsHost && IsPeerConnected && IsHostReady && IsGuestReady;
    public RemotePaddle Opponent { get; } = new();

    // throws InvalidOperationException when the port can't be bound
    public static NetSession Host(ushort port)
    {
        var server = NetServer.Start(port, maxClients: 1);
        var session = new NetSession(server, null);
        server.ClientConnected += session.OnGuestJoined;
        server.ClientDisconnected += _ => session.Ended?.Invoke("Opponent left the game.");
        ReadyRpc.On(server, session.OnGuestReady);
        PaddleRpc.On(server, (_, y) => session.Opponent.Record(y));
        return session;
    }

    // RPCs are registered before the connection goes out, so none arrives without a handler
    public static NetSession Join(string address, ushort port)
    {
        var client = NetClient.Connect(address, port, Tuning.ConnectTimeoutMs);
        var session = new NetSession(null, client);
        client.Connected += session.OnJoinedHost;
        client.Disconnected += status => session.Ended?.Invoke(
            status == NetClientStatus.TimedOut ? "Could not reach host." : "Disconnected from host.");
        LobbyRpc.On(client, session.OnLobby);
        StartRpc.On(client, () => session.MatchStarted?.Invoke());
        PaddleRpc.On(client, session.Opponent.Record);
        BallRpc.On(client, (x, y, vx, vy) => session.BallReceived?.Invoke(new Vector2(x, y), new Vector2(vx, vy)));
        ScoreRpc.On(client, (one, two, scorer) => session.ScoreReceived?.Invoke(one, two, scorer));
        ServeRpc.On(client, () => session.ServeReceived?.Invoke());
        return session;
    }

    public void ToggleReady()
    {
        if (server is not null)
        {
            IsHostReady = !IsHostReady;
            SendLobby(server);
        }
        else
        {
            IsGuestReady = !IsGuestReady;
            ReadyRpc.Send(client!, IsGuestReady);
        }

        LobbyChanged?.Invoke();
    }

    public void StartMatch()
    {
        if (!CanStart)
        {
            return;
        }

        StartRpc.Send(server!, null);
        MatchStarted?.Invoke();
    }

    // ages the opponent's paddle report, and says when the next state update is due
    public bool Tick(float deltaTime)
    {
        Opponent.Advance(deltaTime);
        sendTimer -= deltaTime;
        if (sendTimer > 0.0f)
        {
            return false;
        }

        sendTimer += Tuning.SendInterval;
        sendTimer = MathF.Max(sendTimer, 0.0f);
        return true;
    }

    public void SendPaddle(float y)
    {
        if (server is not null)
        {
            PaddleRpc.Send(server, guest, y, isReliable: false);
        }
        else
        {
            PaddleRpc.Send(client!, y, isReliable: false);
        }
    }

    public void SendBall(Vector2 position, Vector2 velocity) =>
        BallRpc.Send(server!, guest, position.X, position.Y, velocity.X, velocity.Y, isReliable: false);

    public void SendScore(int one, int two, int scorer) => ScoreRpc.Send(server!, guest, one, two, scorer);

    public void SendServe() => ServeRpc.Send(server!, guest);

    // safe from inside one of this session's own events, the endpoint closes once the tick that raised it is done
    public void Dispose()
    {
        server?.Dispose();
        client?.Dispose();
    }

    void OnGuestJoined(NetClientId id)
    {
        guest = id;
        IsPeerConnected = true;
        IsGuestReady = false;
        // the guest doesn't know what the host toggled before it arrived
        SendLobby(server!);
        PeerConnected?.Invoke();
    }

    void OnGuestReady(NetClientId _, bool isReady)
    {
        IsGuestReady = isReady;
        SendLobby(server!);
        LobbyChanged?.Invoke();
    }

    void OnJoinedHost()
    {
        IsPeerConnected = true;
        PeerConnected?.Invoke();
    }

    void OnLobby(bool isHostReady, bool isGuestReady)
    {
        IsHostReady = isHostReady;
        IsGuestReady = isGuestReady;
        LobbyChanged?.Invoke();
    }

    void SendLobby(NetServer host) => LobbyRpc.Send(host, guest, IsHostReady, IsGuestReady);
}

// the opponent's paddle as reported over the network, played back between the last two reports so it moves smoothly
// at the send rate
sealed class RemotePaddle
{
    float previousY;
    float latestY;
    float age;
    bool isKnown;

    public void Record(float y)
    {
        previousY = isKnown ? latestY : y;
        latestY = y;
        age = 0.0f;
        isKnown = true;
    }

    public void Advance(float deltaTime) => age += deltaTime;

    public bool TrySample(out float y, out float velocity)
    {
        var span = latestY - previousY;
        var t = MathF.Min(age / Tuning.PaddleInterpolationWindow, 1.0f);
        y = previousY + span * t;
        velocity = t < 1.0f ? span / Tuning.PaddleInterpolationWindow : 0.0f;
        return isKnown;
    }
}
