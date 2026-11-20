using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

[ApiController, Authorize]
[Route("api/statistics")]
public class StatisticsController : ControllerBase
{
    private const int DailyGoalSeconds = 600;   // seuil pour valider un jour de série (RG05)
    private readonly AppDbContext _db;
    public StatisticsController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet("dashboard")]
    public async Task<IActionResult> Dashboard()
    {
        var user = await _db.Users.AsNoTracking().FirstAsync(u => u.Id == UserId);
        TimeZoneInfo tz;
        try { tz = TimeZoneInfo.FindSystemTimeZoneById(user.TimeZone); }
        catch { tz = TimeZoneInfo.Utc; }

        var raw = await _db.StudySessions.AsNoTracking()
            .Where(s => s.UserId == UserId && s.Status == SessionStatus.Completed)
            .Select(s => new { s.SubjectId, s.AccumulatedSeconds, s.StartedAtUtc })
            .ToListAsync();

        var items = raw.Select(s => new
        {
            s.SubjectId,
            Seconds = s.AccumulatedSeconds,
            Day = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(
                      DateTime.SpecifyKind(s.StartedAtUtc, DateTimeKind.Utc), tz))
        }).ToList();

        var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, tz));
        var weekStart = today.AddDays(-(((int)today.DayOfWeek + 6) % 7));   // lundi
        var monthStart = new DateOnly(today.Year, today.Month, 1);

        var byDay = items.GroupBy(i => i.Day).ToDictionary(g => g.Key, g => g.Sum(x => x.Seconds));
        int Sum(Func<DateOnly, bool> filter) => items.Where(i => filter(i.Day)).Sum(i => i.Seconds);

        // Série en cours : jours consécutifs >= seuil, en finissant aujourd'hui (ou hier si aujourd'hui n'est pas encore atteint)
        bool Valid(DateOnly d) => byDay.GetValueOrDefault(d) >= DailyGoalSeconds;
        var cursor = Valid(today) ? today : today.AddDays(-1);
        int current = 0;
        while (Valid(cursor)) { current++; cursor = cursor.AddDays(-1); }

        // Meilleure série
        int best = 0, run = 0; DateOnly? prev = null;
        foreach (var d in byDay.Where(kv => kv.Value >= DailyGoalSeconds).Select(kv => kv.Key).OrderBy(d => d))
        {
            run = prev is not null && d == prev.Value.AddDays(1) ? run + 1 : 1;
            best = Math.Max(best, run);
            prev = d;
        }

        var subjectNames = await _db.Subjects.AsNoTracking().Where(s => s.UserId == UserId)
            .ToDictionaryAsync(s => s.Id, s => s.Name);
        var bySubject = items.GroupBy(i => i.SubjectId)
            .Select(g => new
            {
                SubjectId = g.Key,
                Name = g.Key is not null && subjectNames.TryGetValue(g.Key.Value, out var n) ? n : "Sans matière",
                Seconds = g.Sum(x => x.Seconds)
            })
            .OrderByDescending(x => x.Seconds).ToList();

        var last7Days = Enumerable.Range(0, 7).Select(i => today.AddDays(i - 6))
            .Select(d => new { Date = d, Seconds = byDay.GetValueOrDefault(d) }).ToList();

        return Ok(new
        {
            TimeZone = tz.Id,
            TotalSeconds = items.Sum(i => i.Seconds),
            TodaySeconds = Sum(d => d == today),
            WeekSeconds = Sum(d => d >= weekStart),
            MonthSeconds = Sum(d => d >= monthStart),
            SessionsCount = items.Count,
            AverageSessionSeconds = items.Count == 0 ? 0 : (int)items.Average(i => i.Seconds),
            CurrentStreakDays = current,
            BestStreakDays = best,
            DailyGoalSeconds,
            BySubject = bySubject,
            Last7Days = last7Days
        });
    }
}
