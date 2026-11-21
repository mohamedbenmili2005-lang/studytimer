using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace StudyTimer.Tests;

/// <summary>Tests des modules ajoutes : amis, confidentialite, taches, salles, invitations, notifications.</summary>
public class ExtrasTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public ExtrasTests(ApiFactory factory) => _factory = factory;

    private static int _n;
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);
    private record Tokens(string Token, string RefreshToken);

    private async Task<(HttpClient client, string username)> NewUser()
    {
        var i = Interlocked.Increment(ref _n);
        var username = $"extra{i}";
        var client = _factory.CreateClient();
        var r = await client.PostAsJsonAsync("/api/auth/register", new
        {
            firstName = "Extra", lastName = "User", username, email = $"{username}@test.com",
            password = "MotDePasse123", country = "MA", timeZone = "UTC"
        });
        r.EnsureSuccessStatusCode();
        var t = (await r.Content.ReadFromJsonAsync<Tokens>(Web))!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", t.Token);
        return (client, username);
    }

    private static async Task<JsonElement> Json(HttpClient c, string url) =>
        await c.GetFromJsonAsync<JsonElement>(url, Web);

    private async Task MakeFriends(HttpClient a, HttpClient b, string bName)
    {
        Assert.Equal(HttpStatusCode.OK, (await a.PostAsJsonAsync("/api/friends/invite", new { username = bName })).StatusCode);
        var reqs = await Json(b, "/api/friends/requests");
        var id = reqs[0].GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/friends/{id}/accept", null)).StatusCode);
    }

    [Fact]
    public async Task Amis_invitation_acceptation_liste_et_notification()
    {
        var (a, _) = await NewUser();
        var (b, bName) = await NewUser();
        await MakeFriends(a, b, bName);

        Assert.Equal(1, (await Json(a, "/api/friends")).GetArrayLength());
        Assert.Equal(1, (await Json(b, "/api/friends")).GetArrayLength());
        Assert.Equal(HttpStatusCode.Conflict,
            (await a.PostAsJsonAsync("/api/friends/invite", new { username = bName })).StatusCode);

        var notifs = await Json(b, "/api/notifications");
        Assert.True(notifs.GetProperty("unread").GetInt32() >= 1);
        var nid = notifs.GetProperty("items")[0].GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/notifications/{nid}/read", null)).StatusCode);
    }

    [Fact]
    public async Task Amis_inconnu_ou_soi_meme_refuse()
    {
        var (a, aName) = await NewUser();
        Assert.Equal(HttpStatusCode.NotFound,
            (await a.PostAsJsonAsync("/api/friends/invite", new { username = "personne-inconnue" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await a.PostAsJsonAsync("/api/friends/invite", new { username = aName })).StatusCode);
    }

    [Fact]
    public async Task Confidentialite_RG07_masque_les_statistiques_aux_amis()
    {
        var (a, _) = await NewUser();
        var (b, bName) = await NewUser();
        await MakeFriends(a, b, bName);
        var bId = (await Json(a, "/api/friends"))[0].GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.OK, (await a.GetAsync($"/api/friends/{bId}/stats")).StatusCode);
        var put = await b.PutAsJsonAsync("/api/users/privacy", new { showStats = false, showActivity = true });
        Assert.Equal(HttpStatusCode.NoContent, put.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await a.GetAsync($"/api/friends/{bId}/stats")).StatusCode);
    }

    [Fact]
    public async Task Statistiques_d_un_non_ami_refusees()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        var bId = (await Json(b, "/api/users/profile")).GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.Forbidden, (await a.GetAsync($"/api/friends/{bId}/stats")).StatusCode);
    }

    [Fact]
    public async Task Classement_entre_amis_contient_moi()
    {
        var (a, _) = await NewUser();
        var r = await Json(a, "/api/friends/leaderboard?period=week");
        Assert.Equal(1, r.GetArrayLength());
        Assert.True(r[0].GetProperty("isMe").GetBoolean());
    }

    [Fact]
    public async Task Taches_creation_liste_retard_et_terminaison()
    {
        var (c, _) = await NewUser();
        var past = DateTime.UtcNow.AddDays(-1);
        var r = await c.PostAsJsonAsync("/api/tasks", new { title = "Revoir le chapitre 3", dueAtUtc = past, estimatedMinutes = 45, priority = "High" });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var id = (await r.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        Assert.Equal(1, (await Json(c, "/api/tasks")).GetArrayLength());
        Assert.Equal(1, (await Json(c, "/api/tasks/overdue")).GetArrayLength());

        Assert.Equal(HttpStatusCode.OK, (await c.PostAsync($"/api/tasks/{id}/complete", null)).StatusCode);
        Assert.Equal(0, (await Json(c, "/api/tasks/overdue")).GetArrayLength());
        Assert.Equal(1, (await Json(c, "/api/tasks?status=done")).GetArrayLength());
    }

    [Fact]
    public async Task Taches_validation_et_isolation()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        Assert.Equal(HttpStatusCode.BadRequest, (await a.PostAsJsonAsync("/api/tasks", new { title = "" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await a.PostAsJsonAsync("/api/tasks", new { title = "x", priority = "Urgent" })).StatusCode);

        var r = await a.PostAsJsonAsync("/api/tasks", new { title = "Priv\u00e9e" });
        var id = (await r.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NotFound, (await b.PostAsync($"/api/tasks/{id}/complete", null)).StatusCode);
        Assert.Equal(0, (await Json(b, "/api/tasks")).GetArrayLength());
    }

    [Fact]
    public async Task Seance_associee_a_une_tache()
    {
        var (c, _) = await NewUser();
        var t = await c.PostAsJsonAsync("/api/tasks", new { title = "Exercices" });
        var taskId = (await t.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        var ok = await c.PostAsJsonAsync("/api/sessions/start", new { mode = "Focus", taskId });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        await c.PostAsync("/api/sessions/stop", null);

        var bad = await c.PostAsJsonAsync("/api/sessions/start", new { mode = "Focus", taskId = Guid.NewGuid() });
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);
    }

    [Fact]
    public async Task Salles_creation_code_messages_et_acces_reserve_aux_membres()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        var (outsider, _) = await NewUser();

        var r = await a.PostAsJsonAsync("/api/rooms", new { name = "R\u00e9visions", isPublic = false });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var created = await r.Content.ReadFromJsonAsync<JsonElement>(Web);
        var id = created.GetProperty("id").GetGuid();
        var code = created.GetProperty("code").GetString()!;
        Assert.Equal(6, code.Length);

        Assert.Equal(HttpStatusCode.OK, (await b.PostAsJsonAsync("/api/rooms/join", new { code = code.ToLower() })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await outsider.PostAsJsonAsync("/api/rooms/join", new { code = "ZZZZZZ" })).StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await b.PostAsJsonAsync($"/api/rooms/{id}/messages", new { text = "Bonjour !" })).StatusCode);
        var msgs = await Json(a, $"/api/rooms/{id}/messages");
        Assert.Equal(1, msgs.GetArrayLength());
        Assert.Equal("Bonjour !", msgs[0].GetProperty("text").GetString());

        var room = await Json(a, $"/api/rooms/{id}");
        Assert.Equal(2, room.GetProperty("participants").GetArrayLength());
        Assert.Equal("Offline", room.GetProperty("participants")[0].GetProperty("status").GetString());

        Assert.Equal(HttpStatusCode.Forbidden, (await outsider.GetAsync($"/api/rooms/{id}/messages")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await outsider.PostAsync($"/api/rooms/{id}/join", null)).StatusCode);
    }

    [Fact]
    public async Task Salles_publiques_visibles_et_salle_supprimee_quand_vide()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        var r = await a.PostAsJsonAsync("/api/rooms", new { name = "Biblioth\u00e8que", isPublic = true });
        var id = (await r.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        var list = await Json(b, "/api/rooms");
        Assert.Contains(list.EnumerateArray(), x => x.GetProperty("id").GetGuid() == id);
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/rooms/{id}/join", null)).StatusCode);

        await a.PostAsync($"/api/rooms/{id}/leave", null);
        await b.PostAsync($"/api/rooms/{id}/leave", null);
        Assert.Equal(HttpStatusCode.NotFound, (await b.GetAsync($"/api/rooms/{id}")).StatusCode);
    }

    [Fact]
    public async Task Invitation_a_un_defi_acceptation_et_classement()
    {
        var (a, _) = await NewUser();
        var (b, bName) = await NewUser();
        var c = await a.PostAsJsonAsync("/api/challenges", new { title = "Semaine intense", type = "TotalTime", target = 600, durationDays = 7 });
        var cid = (await c.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.OK, (await a.PostAsJsonAsync($"/api/challenges/{cid}/invite", new { username = bName })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await a.PostAsJsonAsync($"/api/challenges/{cid}/invite", new { username = bName })).StatusCode);

        var pending = await Json(b, "/api/challenges/invitations");
        Assert.Equal(1, pending.GetArrayLength());
        var invId = pending[0].GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/challenges/invitations/{invId}/accept", null)).StatusCode);

        Assert.Equal(2, (await Json(b, $"/api/challenges/{cid}/ranking")).GetArrayLength());
    }

    [Fact]
    public async Task Routes_du_cahier_et_heatmap()
    {
        var (a, _) = await NewUser();
        Assert.Equal(HttpStatusCode.OK, (await a.GetAsync("/api/leaderboard/weekly")).StatusCode);
        Assert.Equal(30, (await Json(a, "/api/statistics/heatmap?days=30")).GetArrayLength());
    }

    [Fact]
    public async Task Nouvelles_routes_protegees_refusent_sans_token()
    {
        var anon = _factory.CreateClient();
        foreach (var url in new[] { "/api/friends", "/api/tasks", "/api/rooms", "/api/notifications", "/api/statistics/heatmap" })
            Assert.Equal(HttpStatusCode.Unauthorized, (await anon.GetAsync(url)).StatusCode);
    }
}