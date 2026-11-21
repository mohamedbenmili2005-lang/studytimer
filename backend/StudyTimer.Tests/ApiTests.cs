using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace StudyTimer.Tests;

public class ApiTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public ApiTests(ApiFactory factory) => _factory = factory;

    private static int _n;
    private static object NewUser() { var i = Interlocked.Increment(ref _n); return new
    {
        firstName = "Test", lastName = "User", username = $"user{i}", email = $"user{i}@test.com",
        password = "MotDePasse123", country = "MA", timeZone = "UTC"
    }; }

    private record Tokens(string Token, string RefreshToken);

    private async Task<(HttpClient client, Tokens tokens)> Authed()
    {
        var client = _factory.CreateClient();
        var r = await client.PostAsJsonAsync("/api/auth/register", NewUser());
        r.EnsureSuccessStatusCode();
        var t = (await r.Content.ReadFromJsonAsync<Tokens>(new JsonSerializerOptions(JsonSerializerDefaults.Web)))!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", t.Token);
        return (client, t);
    }

    [Fact]
    public async Task Health_endpoint_repond()
    {
        var r = await _factory.CreateClient().GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
    }

    [Fact]
    public async Task Routes_protegees_refusent_sans_token()
    {
        var r = await _factory.CreateClient().GetAsync("/api/sessions/current");
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
    }

    [Fact]
    public async Task Inscription_refuse_mot_de_passe_court()
    {
        var u = NewUser();
        var body = JsonSerializer.SerializeToElement(u);
        var dict = JsonSerializer.Deserialize<Dictionary<string, object>>(body.GetRawText())!;
        dict["password"] = "court";
        var r = await _factory.CreateClient().PostAsJsonAsync("/api/auth/register", dict);
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
    }

    [Fact]
    public async Task Inscription_refuse_email_deja_utilise()
    {
        var c = _factory.CreateClient();
        var u = NewUser();
        Assert.Equal(HttpStatusCode.OK, (await c.PostAsJsonAsync("/api/auth/register", u)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await c.PostAsJsonAsync("/api/auth/register", u)).StatusCode);
    }

    [Fact]
    public async Task Connexion_mauvais_mot_de_passe_refusee()
    {
        var c = _factory.CreateClient();
        var u = NewUser();
        await c.PostAsJsonAsync("/api/auth/register", u);
        var email = JsonSerializer.SerializeToElement(u).GetProperty("email").GetString();
        var r = await c.PostAsJsonAsync("/api/auth/login", new { email, password = "mauvais-mot-de-passe" });
        Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
    }

    [Fact]
    public async Task Refresh_token_est_a_usage_unique()
    {
        var (client, t) = await Authed();
        var first = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = t.RefreshToken });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        var second = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = t.RefreshToken });
        Assert.Equal(HttpStatusCode.Unauthorized, second.StatusCode);
    }

    [Fact]
    public async Task Cycle_complet_de_seance_et_historique()
    {
        var (c, _) = await Authed();

        Assert.Equal(HttpStatusCode.OK, (await c.PostAsJsonAsync("/api/sessions/start", new { mode = "Focus", targetSeconds = 1500 })).StatusCode);
        // Une seule séance active à la fois
        Assert.Equal(HttpStatusCode.Conflict, (await c.PostAsJsonAsync("/api/sessions/start", new { mode = "Focus" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.PostAsync("/api/sessions/pause", null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.PostAsync("/api/sessions/resume", null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.PostAsync("/api/sessions/stop", null)).StatusCode);

        var history = await c.GetFromJsonAsync<JsonElement>("/api/sessions/history");
        Assert.Equal(1, history.GetArrayLength());
        Assert.Equal("Completed", history[0].GetProperty("status").GetString());
    }

    [Fact]
    public async Task Demarrage_refuse_mode_invalide()
    {
        var (c, _) = await Authed();
        var r = await c.PostAsJsonAsync("/api/sessions/start", new { mode = "Nimporte" });
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
    }

    [Fact]
    public async Task Matieres_creation_sans_doublon_et_isolation_par_utilisateur()
    {
        var (a, _) = await Authed();
        var (b, _) = await Authed();

        var s1 = await (await a.PostAsJsonAsync("/api/subjects", new { name = "Maths" })).Content.ReadFromJsonAsync<JsonElement>();
        var s2 = await (await a.PostAsJsonAsync("/api/subjects", new { name = "maths" })).Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(s1.GetProperty("id").GetString(), s2.GetProperty("id").GetString());

        Assert.Equal(1, (await a.GetFromJsonAsync<JsonElement>("/api/subjects")).GetArrayLength());
        Assert.Equal(0, (await b.GetFromJsonAsync<JsonElement>("/api/subjects")).GetArrayLength());

        // B ne peut pas utiliser la matière de A
        var r = await b.PostAsJsonAsync("/api/sessions/start", new { mode = "Focus", subjectId = s1.GetProperty("id").GetString() });
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
    }

    [Fact]
    public async Task Statistiques_tableau_de_bord_disponible()
    {
        var (c, _) = await Authed();
        var r = await c.GetAsync("/api/statistics/dashboard");
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var d = await r.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(0, d.GetProperty("totalSeconds").GetInt32());
        Assert.Equal(7, d.GetProperty("last7Days").GetArrayLength());
    }

    [Fact]
    public async Task Profil_modification_refuse_fuseau_inconnu()
    {
        var (c, _) = await Authed();
        var r = await c.PutAsJsonAsync("/api/users/profile",
            new { firstName = "A", lastName = "B", country = "MA", timeZone = "Mars/Olympus" });
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
    }

    [Fact]
    public async Task Defi_creation_participation_et_classement()
    {
        var (a, _) = await Authed();
        var (b, _) = await Authed();

        var created = await a.PostAsJsonAsync("/api/challenges",
            new { title = "10 h cette semaine", type = "TotalTime", target = 36000, durationDays = 7 });
        Assert.Equal(HttpStatusCode.OK, created.StatusCode);
        var id = (await created.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetString();

        // Non participant : classement interdit
        Assert.Equal(HttpStatusCode.Forbidden, (await b.GetAsync($"/api/challenges/{id}/leaderboard")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/challenges/{id}/join", null)).StatusCode);

        var board = await b.GetFromJsonAsync<JsonElement>($"/api/challenges/{id}/leaderboard");
        Assert.Equal(2, board.GetArrayLength());
    }

    [Fact]
    public async Task Defi_refuse_type_invalide()
    {
        var (c, _) = await Authed();
        var r = await c.PostAsJsonAsync("/api/challenges",
            new { title = "x", type = "Nimporte", target = 10, durationDays = 3 });
        Assert.Equal(HttpStatusCode.BadRequest, r.StatusCode);
    }

    [Fact]
    public async Task Progression_xp_niveau_et_badges()
    {
        var (c, _) = await Authed();
        var r = await c.GetFromJsonAsync<JsonElement>("/api/progress");
        Assert.Equal(0, r.GetProperty("xp").GetInt32());
        Assert.Equal(1, r.GetProperty("level").GetInt32());
        Assert.Equal(8, r.GetProperty("badges").GetArrayLength());
    }
}
