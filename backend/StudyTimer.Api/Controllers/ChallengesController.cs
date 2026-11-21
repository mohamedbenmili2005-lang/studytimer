using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record CreateChallengeDto(string Title, string Type, int Target, int DurationDays, bool IsPublic = true);

[ApiController, Authorize]
[Route("api/challenges")]
public class ChallengesController : ControllerBase
{
    private readonly AppDbContext _db;
    public ChallengesController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    private async Task<List<(DateTime startedUtc, int seconds)>> SessionsOf(Guid userId) =>
        (await _db.StudySessions.AsNoTracking()
            .Where(s => s.UserId == userId && s.Status == SessionStatus.Completed)
            .Select(s => new { s.StartedAtUtc, s.AccumulatedSeconds })
            .ToListAsync())
        .Select(s => (s.StartedAtUtc, s.AccumulatedSeconds)).ToList();

    /// <summary>Défis publics en cours ou à venir + ceux de l'utilisateur, avec sa progression.</summary>
    [HttpGet]
    public async Task<IActionResult> List()
    {
        var now = DateTime.UtcNow;
        var mine = await _db.ChallengeParticipants.AsNoTracking()
            .Where(p => p.UserId == UserId).Select(p => p.ChallengeId).ToListAsync();

        var challenges = await _db.Challenges.AsNoTracking()
            .Where(c => mine.Contains(c.Id) || (c.IsPublic && c.EndsAtUtc >= now))
            .OrderBy(c => c.EndsAtUtc)
            .Take(100)
            .ToListAsync();

        var cids = challenges.Select(c => c.Id).ToList();
        var counts = await _db.ChallengeParticipants.AsNoTracking()
            .Where(p => cids.Contains(p.ChallengeId))
            .GroupBy(p => p.ChallengeId)
            .Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N);

        var my = await SessionsOf(UserId);
        return Ok(challenges.Select(c => new
        {
            c.Id, c.Title, Type = c.Type.ToString(), c.Target, c.StartsAtUtc, c.EndsAtUtc,
            Participants = counts.GetValueOrDefault(c.Id),
            Joined = mine.Contains(c.Id),
            Progress = mine.Contains(c.Id) ? Gamification.Progress(c, my) : 0,
            Finished = c.EndsAtUtc < now
        }));
    }

    [HttpPost]
    public async Task<IActionResult> Create(CreateChallengeDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Title) || dto.Title.Trim().Length > 80)
            return BadRequest("Titre requis (80 caractères max).");
        if (!Enum.TryParse<ChallengeType>(dto.Type, true, out var type))
            return BadRequest("Type de défi invalide.");
        if (dto.Target <= 0) return BadRequest("Objectif invalide.");
        if (dto.DurationDays is < 1 or > 90) return BadRequest("Durée : 1 à 90 jours.");

        var now = DateTime.UtcNow;
        var c = new Challenge
        {
            CreatorId = UserId,
            Title = dto.Title.Trim(),
            Type = type,
            Target = dto.Target,
            StartsAtUtc = now,
            EndsAtUtc = now.AddDays(dto.DurationDays),
            IsPublic = dto.IsPublic
        };
        c.Participants.Add(new ChallengeParticipant { UserId = UserId });
        _db.Challenges.Add(c);
        await _db.SaveChangesAsync();
        return Ok(new { c.Id });
    }

    [HttpPost("{id:guid}/join")]
    public async Task<IActionResult> Join(Guid id)
    {
        var c = await _db.Challenges.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (c is null || (!c.IsPublic && c.CreatorId != UserId)) return NotFound();
        if (c.EndsAtUtc < DateTime.UtcNow) return BadRequest("Ce défi est terminé.");
        if (!await _db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == id && p.UserId == UserId))
        {
            _db.ChallengeParticipants.Add(new ChallengeParticipant { ChallengeId = id, UserId = UserId });
            await _db.SaveChangesAsync();
        }
        return NoContent();
    }

    /// <summary>Classement des participants d'un défi (réservé aux participants).</summary>
    [HttpGet("{id:guid}/leaderboard")]
    public async Task<IActionResult> Leaderboard(Guid id)
    {
        var c = await _db.Challenges.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (c is null) return NotFound();
        var ids = await _db.ChallengeParticipants.AsNoTracking()
            .Where(p => p.ChallengeId == id).Select(p => p.UserId).ToListAsync();
        if (!ids.Contains(UserId)) return Forbid();

        var names = await _db.Users.AsNoTracking().Where(u => ids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);

        var all = (await _db.StudySessions.AsNoTracking()
            .Where(s => ids.Contains(s.UserId) && s.Status == SessionStatus.Completed
                        && s.StartedAtUtc >= c.StartsAtUtc && s.StartedAtUtc <= c.EndsAtUtc)
            .Select(s => new { s.UserId, s.StartedAtUtc, s.AccumulatedSeconds })
            .ToListAsync())
            .GroupBy(s => s.UserId)
            .ToDictionary(g => g.Key, g => g.Select(s => (s.StartedAtUtc, s.AccumulatedSeconds)).ToList());

        var ranking = ids
            .Select(uid => new
            {
                Username = names.GetValueOrDefault(uid, "?"),
                Progress = Gamification.Progress(c, all.GetValueOrDefault(uid) ?? new()),
                IsMe = uid == UserId
            })
            .OrderByDescending(x => x.Progress)
            .Select((x, i) => new { Rank = i + 1, x.Username, x.Progress, x.IsMe, Completed = x.Progress >= c.Target });
        return Ok(ranking);
    }
}
