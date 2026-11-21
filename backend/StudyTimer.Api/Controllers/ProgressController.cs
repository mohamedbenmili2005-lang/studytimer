using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

[ApiController, Authorize]
[Route("api")]
public class ProgressController : ControllerBase
{
    private readonly AppDbContext _db;
    public ProgressController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    /// <summary>XP, niveau et badges (attribue les nouveaux badges mérités).</summary>
    [HttpGet("progress")]
    public async Task<IActionResult> Progress()
    {
        var rows = await _db.StudySessions.AsNoTracking()
            .Where(s => s.UserId == UserId && s.Status == SessionStatus.Completed)
            .Select(s => new { s.StartedAtUtc, s.AccumulatedSeconds, s.XpAwarded })
            .ToListAsync();

        var xp = rows.Sum(r => r.XpAwarded);
        var (level, into, forNext) = Gamification.Level(xp);

        var sessions = rows.Select(r => (DateOnly.FromDateTime(r.StartedAtUtc), r.AccumulatedSeconds)).ToList();
        var earned = Gamification.Earned(sessions);

        var stored = await _db.UserBadges.Where(b => b.UserId == UserId).ToListAsync();
        foreach (var code in earned.Where(c => stored.All(b => b.Code != c)))
        {
            var ub = new UserBadge { UserId = UserId, Code = code };
            _db.UserBadges.Add(ub);
            stored.Add(ub);
        }
        await _db.SaveChangesAsync();

        return Ok(new
        {
            Xp = xp,
            Level = level,
            XpIntoLevel = into,
            XpForNextLevel = forNext,
            Badges = Gamification.Badges.Select(b => new
            {
                b.Code, b.Name, b.Description, b.Icon,
                Earned = stored.Any(s => s.Code == b.Code),
                EarnedAtUtc = stored.FirstOrDefault(s => s.Code == b.Code)?.EarnedAtUtc
            })
        });
    }

    /// <summary>Classement général : period = week | month | all.</summary>
    [HttpGet("leaderboard")]
    public async Task<IActionResult> Leaderboard([FromQuery] string period = "week")
    {
        var now = DateTime.UtcNow;
        var from = period switch
        {
            "month" => new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc),
            "all" => DateTime.MinValue,
            _ => now.Date.AddDays(-(((int)now.DayOfWeek + 6) % 7))   // lundi 00:00 UTC
        };

        var rows = await _db.StudySessions.AsNoTracking()
            .Where(s => s.Status == SessionStatus.Completed && s.StartedAtUtc >= from)
            .GroupBy(s => s.UserId)
            .Select(g => new { UserId = g.Key, Seconds = g.Sum(x => x.AccumulatedSeconds), Xp = g.Sum(x => x.XpAwarded) })
            .OrderByDescending(x => x.Seconds)
            .Take(50)
            .ToListAsync();

        var ids = rows.Select(r => r.UserId).ToList();
        var names = await _db.Users.AsNoTracking().Where(u => ids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);

        var list = rows.Select((r, i) => new
        {
            Rank = i + 1,
            Username = names.GetValueOrDefault(r.UserId, "?"),
            r.Seconds,
            r.Xp,
            IsMe = r.UserId == UserId
        });
        return Ok(list);
    }
}
