using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

/// <summary>Calendrier d'activite (heatmap) : secondes etudiees par jour, dans le fuseau de l'utilisateur.</summary>
[ApiController, Authorize]
[Route("api/statistics")]
public class StatisticsExtrasController : ControllerBase
{
    private readonly AppDbContext _db;
    public StatisticsExtrasController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet("heatmap")]
    public async Task<IActionResult> Heatmap([FromQuery] int days = 365)
    {
        days = Math.Clamp(days, 7, 730);
        var user = await _db.Users.AsNoTracking().FirstAsync(u => u.Id == UserId);
        TimeZoneInfo tz;
        try { tz = TimeZoneInfo.FindSystemTimeZoneById(user.TimeZone); }
        catch { tz = TimeZoneInfo.Utc; }

        var since = DateTime.UtcNow.AddDays(-days - 1);
        var raw = await _db.StudySessions.AsNoTracking()
            .Where(s => s.UserId == UserId && s.Status == SessionStatus.Completed && s.StartedAtUtc >= since)
            .Select(s => new { s.StartedAtUtc, s.AccumulatedSeconds })
            .ToListAsync();

        var byDay = raw
            .GroupBy(s => DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(
                DateTime.SpecifyKind(s.StartedAtUtc, DateTimeKind.Utc), tz)))
            .ToDictionary(g => g.Key, g => g.Sum(x => x.AccumulatedSeconds));

        var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, tz));
        return Ok(Enumerable.Range(0, days)
            .Select(i => today.AddDays(i - days + 1))
            .Select(d => new { Date = d, Seconds = byDay.GetValueOrDefault(d) }));
    }
}

/// <summary>Routes alias conformes au cahier des charges (section 5).</summary>
[ApiController, Authorize]
[Route("api")]
public class CahierAliasController : ControllerBase
{
    private readonly AppDbContext _db;
    public CahierAliasController(AppDbContext db) => _db = db;

    /// <summary>GET /api/leaderboard/weekly = /api/leaderboard?period=week</summary>
    [HttpGet("leaderboard/weekly")]
    public Task<IActionResult> Weekly() =>
        new ProgressController(_db) { ControllerContext = ControllerContext }.Leaderboard("week");

    /// <summary>GET /api/challenges/{id}/ranking = /api/challenges/{id}/leaderboard</summary>
    [HttpGet("challenges/{id:guid}/ranking")]
    public Task<IActionResult> Ranking(Guid id) =>
        new ChallengesController(_db) { ControllerContext = ControllerContext }.Leaderboard(id);
}