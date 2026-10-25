using System;
using System.Collections.Generic;

using Oxylus;

namespace Pong;

enum Panel
{
    MainMenu,
    LocalLobby,
    OnlineMenu,
    OnlineLobby,
    Game,
}

enum MenuAction
{
    PlayAi,
    LocalLobby,
    StartLocal,
    OnlineMenu,
    Host,
    Join,
    ToggleReady,
    StartOnline,
    Leave,
    MainMenu,
    Exit,
}

// UI/ui.rml. It only shows things, every button goes to the game as a MenuAction
sealed class Menus : IDisposable
{
    static readonly (string Id, Panel Panel)[] Panels =
    [
        ("main_menu", Panel.MainMenu),
        ("lobby", Panel.LocalLobby),
        ("online_menu", Panel.OnlineMenu),
        ("online_lobby", Panel.OnlineLobby),
        ("game_ui", Panel.Game),
    ];

    static readonly (string Id, MenuAction Action)[] Buttons =
    [
        ("btn_local_ai", MenuAction.PlayAi),
        ("btn_local_coop", MenuAction.LocalLobby),
        ("btn_start", MenuAction.StartLocal),
        ("btn_lobby_back", MenuAction.MainMenu),
        ("btn_online", MenuAction.OnlineMenu),
        ("btn_host", MenuAction.Host),
        ("btn_join", MenuAction.Join),
        ("btn_online_back", MenuAction.MainMenu),
        ("btn_net_ready", MenuAction.ToggleReady),
        ("btn_net_start", MenuAction.StartOnline),
        ("btn_net_leave", MenuAction.Leave),
        ("btn_exit", MenuAction.Exit),
    ];

    readonly UiDataModel model;
    readonly UiDocument document;
    readonly List<UiListener> listeners = [];
    int scoreOne;
    int scoreTwo;
    int pointWinner;
    int countdown;
    // so the first Show hides it, whatever the RML starts with
    bool isBannerVisible = true;

    public Menus(World world, Action<MenuAction> onAction)
    {
        // before the document, which binds to it as it loads
        model = Ui.CreateDataModel(world, "game_state");
        model.Bind("p1_score", () => scoreOne);
        model.Bind("p2_score", () => scoreTwo);
        model.Bind("point_winner", () => pointWinner);
        model.Bind("countdown", () => countdown > 0 ? countdown.ToString() : "");

        document = Ui.LoadDocument(world, "UI/ui.rml");
        foreach (var (id, action) in Buttons)
        {
            listeners.Add(document.GetElementById(id).AddEventListener("click", _ => onAction(action)));
        }

        document.Show();
        Show(Panel.MainMenu);
    }

    public Panel Current { get; private set; }

    public string Address => document.GetElementById("ip_input").GetAttribute("value").Trim();

    public bool TryReadPort(out ushort port) =>
        ushort.TryParse(document.GetElementById("port_input").GetAttribute("value").Trim(), out port) && port != 0;

    public void Show(Panel panel)
    {
        foreach (var (id, each) in Panels)
        {
            document.GetElementById(id).SetProperty("display", each == panel ? "flex" : "none");
        }

        ShowPointBanner(false);
        Current = panel;
    }

    public void ShowStatus(string text) => document.GetElementById("online_status").SetInnerRml(text);

    public void ShowLocalLobby(bool isOneReady, bool isTwoReady)
    {
        ShowReady("p1_status", isOneReady, "Press Up/Down to ready");
        ShowReady("p2_status", isTwoReady, "Press W/S to ready");
        SetVisible("btn_start", isOneReady && isTwoReady);
    }

    public void ShowOnlineLobby(NetSession session, string address)
    {
        document.GetElementById("lobby_address").SetInnerRml(address);
        ShowReady("net_p1_status", session.IsHostReady, "Not ready");
        if (session.IsPeerConnected)
        {
            ShowReady("net_p2_status", session.IsGuestReady, "Not ready");
        }
        else
        {
            ShowReady("net_p2_status", false, "Waiting for opponent...");
        }

        document.GetElementById("btn_net_ready").SetInnerRml(session.IsLocalReady ? "Cancel Ready" : "Ready");
        SetVisible("btn_net_start", session.CanStart);
    }

    public void ShowScore(int one, int two)
    {
        if (one == scoreOne && two == scoreTwo)
        {
            return;
        }

        scoreOne = one;
        scoreTwo = two;
        model.Dirty("p1_score");
        model.Dirty("p2_score");
    }

    // between points, who won the last one and the countdown to the next serve
    public void ShowPointBanner(bool isVisible, int winner = 0, int seconds = 0)
    {
        if (isVisible != isBannerVisible)
        {
            isBannerVisible = isVisible;
            SetVisible("game_end_ui", isVisible, "flex");
        }

        if (winner != pointWinner)
        {
            pointWinner = winner;
            model.Dirty("point_winner");
        }

        if (seconds != countdown)
        {
            countdown = seconds;
            model.Dirty("countdown");
        }
    }

    public void Dispose()
    {
        foreach (var listener in listeners)
        {
            listener.Dispose();
        }

        document.Close();
        model.Dispose();
    }

    void ShowReady(string id, bool isReady, string notReadyText)
    {
        var element = document.GetElementById(id);
        element.SetInnerRml(isReady ? "READY" : notReadyText);
        element.SetClass("ready", isReady);
        element.SetClass("not-ready", !isReady);
    }

    void SetVisible(string id, bool isVisible, string display = "block") =>
        document.GetElementById(id).SetProperty("display", isVisible ? display : "none");
}
