using System;

using Oxylus;

namespace Pong;

// the main scene's script: menus, lobbies and whichever match is being played
public sealed class PongGame : SceneScript
{
    Menus menus = null!;
    Entity background;
    Match? match;
    NetSession? session;
    // shown in the online lobby, the port hosted on or the address joined
    string lobbyAddress = "";
    bool isOneReady;
    bool isTwoReady;

    public override void OnStart()
    {
        background = Arena.SpawnBackground(World);
        menus = new Menus(World, OnMenu);
    }

    public override void OnStop()
    {
        EndMatch();
        session?.Dispose();
        menus.Dispose();
        background.Destruct();
    }

    public override void OnUpdate(float deltaTime)
    {
        if (menus.Current == Panel.LocalLobby)
        {
            UpdateLocalLobby();
        }

        if (match is null)
        {
            return;
        }

        match.Update(deltaTime, World.InputFocused);
        if (session?.Tick(deltaTime) == true)
        {
            session.SendPaddle(match.PaddleY(session.LocalPlayer));
            if (session.IsHost)
            {
                session.SendBall(match.BallPosition, match.BallVelocity);
            }
        }

        menus.ShowScore(match.ScoreOne, match.ScoreTwo);
        menus.ShowPointBanner(match.IsServing, match.LastScorer + 1, match.Countdown);
    }

    public override void OnContact(in Contact contact) => match?.OnContact(contact);

    void OnMenu(MenuAction action)
    {
        switch (action)
        {
            case MenuAction.PlayAi:
                StartMatch(PaddleControl.ArrowKeys, PaddleControl.Ai);
                break;
            case MenuAction.LocalLobby:
                isOneReady = false;
                isTwoReady = false;
                menus.ShowLocalLobby(isOneReady, isTwoReady);
                menus.Show(Panel.LocalLobby);
                break;
            case MenuAction.StartLocal:
                StartMatch(PaddleControl.ArrowKeys, PaddleControl.WsKeys);
                break;
            case MenuAction.OnlineMenu:
                menus.ShowStatus("");
                menus.Show(Panel.OnlineMenu);
                break;
            case MenuAction.Host:
                Host();
                break;
            case MenuAction.Join:
                Join();
                break;
            case MenuAction.ToggleReady:
                session?.ToggleReady();
                break;
            case MenuAction.StartOnline:
                session?.StartMatch();
                break;
            case MenuAction.Leave:
                LeaveSession("");
                break;
            case MenuAction.MainMenu:
                session?.Dispose();
                session = null;
                menus.Show(Panel.MainMenu);
                break;
            case MenuAction.Exit:
                App.Quit();
                break;
        }
    }

    void UpdateLocalLobby()
    {
        if (!World.InputFocused)
        {
            return;
        }

        var isChanged = false;
        if (!isOneReady && (Input.IsKeyPressed(ScanCode.Up) || Input.IsKeyPressed(ScanCode.Down)))
        {
            isOneReady = true;
            isChanged = true;
        }

        if (!isTwoReady && (Input.IsKeyPressed(ScanCode.W) || Input.IsKeyPressed(ScanCode.S)))
        {
            isTwoReady = true;
            isChanged = true;
        }

        if (isChanged)
        {
            menus.ShowLocalLobby(isOneReady, isTwoReady);
        }
    }

    void Host()
    {
        if (!menus.TryReadPort(out var port))
        {
            menus.ShowStatus("Port must be a whole number between 1 and 65535.");
            return;
        }

        try
        {
            Open(NetSession.Host(port), $"Hosting on port {port}");
        }
        catch (InvalidOperationException)
        {
            menus.ShowStatus($"Could not host on port {port}.");
            return;
        }

        ShowOnlineLobby();
    }

    void Join()
    {
        if (!menus.TryReadPort(out var port))
        {
            menus.ShowStatus("Port must be a whole number between 1 and 65535.");
            return;
        }

        var address = menus.Address;
        if (address.Length == 0)
        {
            menus.ShowStatus("Enter the host's IP address.");
            return;
        }

        try
        {
            Open(NetSession.Join(address, port), $"Connected to {address}:{port}");
        }
        catch (InvalidOperationException)
        {
            menus.ShowStatus($"Could not start connecting to {address}:{port}.");
            return;
        }

        menus.ShowStatus($"Connecting to {address}:{port}...");
    }

    void Open(NetSession opened, string address)
    {
        session?.Dispose();
        session = opened;
        lobbyAddress = address;
        opened.PeerConnected += ShowOnlineLobby;
        opened.LobbyChanged += ShowOnlineLobby;
        opened.Ended += LeaveSession;
        opened.MatchStarted += StartOnlineMatch;
        opened.BallReceived += (position, velocity) => match?.CorrectBall(position, velocity);
        opened.ScoreReceived += (one, two, scorer) => match?.ApplyScore(one, two, scorer);
        opened.ServeReceived += () => match?.Resume();
    }

    void ShowOnlineLobby()
    {
        menus.ShowStatus("");
        menus.ShowOnlineLobby(session!, lobbyAddress);
        menus.Show(Panel.OnlineLobby);
    }

    void LeaveSession(string reason)
    {
        EndMatch();
        session?.Dispose();
        session = null;
        menus.Show(Panel.OnlineMenu);
        menus.ShowStatus(reason);
    }

    void StartOnlineMatch()
    {
        if (session!.IsHost)
        {
            StartMatch(PaddleControl.AnyKeys, PaddleControl.Remote, session);
        }
        else
        {
            StartMatch(PaddleControl.Remote, PaddleControl.AnyKeys, session);
        }
    }

    // a match can be replayed within one run, so whatever was spawned for the last one goes first
    void StartMatch(PaddleControl one, PaddleControl two, NetSession? net = null)
    {
        EndMatch();
        var started = new Match(World, one, two, isAuthority: net is null || net.IsHost, net?.Opponent);
        if (net is { IsHost: true })
        {
            started.PointScored += () => net.SendScore(started.ScoreOne, started.ScoreTwo, started.LastScorer);
            started.Served += net.SendServe;
        }

        match = started;
        menus.ShowScore(0, 0);
        menus.Show(Panel.Game);
    }

    void EndMatch()
    {
        match?.Dispose();
        match = null;
    }
}
