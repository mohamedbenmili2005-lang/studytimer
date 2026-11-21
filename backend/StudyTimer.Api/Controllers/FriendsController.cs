using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record InviteFriendDto(string Username);

/// <summary>Module 4 : amis, activite et statistiques des amis (respecte RG07).</summary>
[ApiController, Authorize]
[Route("api/friends")]
public class FriendsController : ControllerBase
{
    private readonly AppDbContext _db;
    public FriendsController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    private async Task<List<Guid>> FriendIds()
    {
        var rows = await _db.Friendships.AsNoTracking()
            .Where(f => f.Status == RequestStatus.Accepted && (f.RequesterId == UserId || f.AddresseeId == UserId))
            .Select(f => new { f.RequesterId, f.AddresseeId })
            .ToListAsync();
        return rows.Select(r => r.RequesterId == UserId ? r.AddresseeId : r.RequesterId).Distinct().ToList();
    }

    private async Task<Dictionary<Guid, string>> Names(IEnumerable<Guid> ids)
    {
        var list = ids.Distinct().ToList();
        return await _db.Users.AsNoTracking().Where(u => list.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
    }

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var ids = await FriendIds();
        var users = await _db.Users.AsNoTracking().Where(u => ids.Contains(u.Id))
            .OrderBy(u => u.Username).Select(u => new { u.Id, u.Username }).ToListAsync();
        return Ok(users);
    }

    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] string q = "")
    {
        q = (q ?? "").Trim().ToLower();
        if (q.Length < 2) return Ok(Array.Empty<object>());
        var users = await _db.Users.AsNoTracking()
            .Where(u => u.Id != UserId && u.Username.ToLower().Contains(q))
            .OrderBy(u => u.Username).Take(10)
            .Select(u => new { u.Id, u.Username }).ToListAsync();
        return Ok(users);
    }

    [HttpPost("invite")]
    public async Task<IActionResult> Invite(InviteFriendDto dto)
    {
        var name = (dto.Username ?? "").Trim().ToLower();
        if (name.Length == 0) return BadRequest("Pseudo requis.");
        var target = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == name);
        if (target is null) return NotFound("Utilisateur introuvable.");
        if (target.Id == UserId) return BadRequest("Vous ne pouvez pas vous inviter vous-m\u00eame.");

        var existing = await _db.Friendships.FirstOrDefaultAsync(f =>
            (f.RequesterId == UserId && f.AddresseeId == target.Id) ||
            (f.RequesterId == target.Id && f.AddresseeId == UserId));
        if (existing is not null)
        {
            if (existing.Status != RequestStatus.Declined) return Conflict("Invitation ou amiti\u00e9 d\u00e9j\u00e0 existante.");
            _db.Friendships.Remove(existing);
            await _db.SaveChangesAsync();
        }

        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        var f = new Friendship { RequesterId = UserId, AddresseeId = target.Id };
        _db.Friendships.Add(f);
        Notifier.Add(_db, target.Id, "friend_invite", "Nouvelle invitation", $"{me} vous invite \u00e0 devenir ami.");
        await _db.SaveChangesAsync();
        return Ok(new { f.Id });
    }

    [HttpGet("requests")]
    public async Task<IActionResult> Requests()
    {
        var rows = await _db.Friendships.AsNoTracking()
            .Where(f => f.AddresseeId == UserId && f.Status == RequestStatus.Pending)
            .OrderByDescending(f => f.CreatedAtUtc)
            .Select(f => new { f.Id, f.RequesterId, f.CreatedAtUtc })
            .ToListAsync();
        var names = await Names(rows.Select(r => r.RequesterId));
        return Ok(rows.Select(r => new
        {
            r.Id, r.RequesterId, Username = names.GetValueOrDefault(r.RequesterId, "?"), r.CreatedAtUtc
        }));
    }

    [HttpPost("{id:guid}/accept")]
    public async Task<IActionResult> Accept(Guid id)
    {
        var f = await _db.Friendships.FirstOrDefaultAsync(x =>
            x.Id == id && x.AddresseeId == UserId && x.Status == RequestStatus.Pending);
        if (f is null) return NotFound();
        f.Status = RequestStatus.Accepted;
        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        Notifier.Add(_db, f.RequesterId, "friend_accepted", "Invitation accept\u00e9e", $"{me} a accept\u00e9 votre invitation.");
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{id:guid}/decline")]
    public async Task<IActionResult> Decline(Guid id)
    {
        var f = await _db.Friendships.FirstOrDefaultAsync(x =>
            x.Id == id && x.AddresseeId == UserId && x.Status == RequestStatus.Pending);
        if (f is null) return NotFound();
        f.Status = RequestStatus.Declined;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{userId:guid}")]
    public async Task<IActionResult> Remove(Guid userId)
    {
        var rows = await _db.Friendships.Where(f =>
            (f.RequesterId == UserId && f.AddresseeId == userId) ||
            (f.RequesterId == userId && f.AddresseeId == UserId)).ToListAsync();
        if (rows.Count == 0) return NotFound();
        _db.Friendships.RemoveRange(rows);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Statistiques publiques d'un ami (RG07 : refuse si l'ami les a masquees).</summary>
    [HttpGet("{userId:guid}/stats")]
    public async Task<IActionResult> FriendStats(Guid userId)
    {
        if (!(await FriendIds()).Contains(userId)) return Forbid();
        var privacy = await _db.UserPrivacies.AsNoTracking().FirstOrDefaultAsync(p => p.UserId == userId);
        if (privacy is not null && !privacy.ShowStats) return Forbid();

        var now = DateTime.UtcNow;
        var weekStart = now.Date.AddDays(-(((int)now.DayOfWeek + 6) % 7));
        var rows = await _db.StudySessions.AsNoTracking()
            .Where(s => s.UserId == userId && s.Status == SessionStatus.Completed)
            .Select(s => new { s.StartedAtUtc, s.AccumulatedSeconds, s.XpAwarded })
            .ToListAsync();
        var xp = rows.Sum(r => r.XpAwarded);
        return Ok(new
        {
            TotalSeconds = rows.Sum(r => r.AccumulatedSeconds),
            WeekSeconds = rows.Where(r => r.StartedAtUtc >= weekStart).Sum(r => r.AccumulatedSeconds),
            SessionsCount = rows.Count,
            Xp = xp,
            Level = Gamification.Level(xp).level
        });
    }

    /// <summary>Activite recente des amis (hors amis qui masquent leur activite).</summary>
    [HttpGet("feed")]
    public async Task<IActionResult> Feed()
    {
        var ids = await FriendIds();
        var hidden = await _db.UserPrivacies.AsNoTracking()
            .Where(p => ids.Contains(p.UserId) && !p.ShowActivity)
            .Select(p => p.UserId).ToListAsync();
        var visible = ids.Except(hidden).ToList();
        var items = await _db.StudySessions.AsNoTracking()
            .Where(s => visible.Contains(s.UserId) && s.Status == SessionStatus.Completed)
            .OrderByDescending(s => s.EndedAtUtc).Take(30)
            .Select(s => new { s.UserId, s.Mode, s.AccumulatedSeconds, s.EndedAtUtc })
            .ToListAsync();
        var names = await Names(items.Select(i => i.UserId));
        return Ok(items.Select(i => new
        {
            Username = names.GetValueOrDefault(i.UserId, "?"),
            Mode = i.Mode.ToString(),
            Seconds = i.AccumulatedSeconds,
            i.EndedAtUtc
        }));
    }

    /// <summary>Classement entre amis (moi inclus) : period = week | month | all.</summary>
    [HttpGet("leaderboard")]
    public async Task<IActionResult> Leaderboard([FromQuery] string period = "week")
    {
        var ids = await FriendIds();
        ids.Add(UserId);
        var now = DateTime.UtcNow;
        var from = period switch
        {
            "month" => new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc),
            "all" => DateTime.MinValue,
            _ => now.Date.AddDays(-(((int)now.DayOfWeek + 6) % 7))
        };
        var rows = await _db.StudySessions.AsNoTracking()
            .Where(s => ids.Contains(s.UserId) && s.Status == SessionStatus.Completed && s.StartedAtUtc >= from)
            .GroupBy(s => s.UserId)
            .Select(g => new { UserId = g.Key, Seconds = g.Sum(x => x.AccumulatedSeconds) })
            .ToListAsync();
        var names = await Names(ids);
        var ranking = ids
            .Select(id => new { Id = id, Seconds = rows.Where(r => r.UserId == id).Sum(r => r.Seconds) })
            .OrderByDescending(x => x.Seconds)
            .Select((x, i) => new
            {
                Rank = i + 1,
                Username = names.GetValueOrDefault(x.Id, "?"),
                x.Seconds,
                IsMe = x.Id == UserId
            });
        return Ok(ranking);
    }
}

public record PrivacyDto(bool ShowStats, bool ShowActivity);

/// <summary>RG07 : choix de visibilite du profil pour les amis.</summary>
[ApiController, Authorize]
[Route("api/users/privacy")]
public class PrivacyController : ControllerBase
{
    private readonly AppDbContext _db;
    public PrivacyController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet]
    public async Task<IActionResult> Get()
    {
        var p = await _db.UserPrivacies.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == UserId);
        return Ok(new { ShowStats = p?.ShowStats ?? true, ShowActivity = p?.ShowActivity ?? true });
    }

    [HttpPut]
    public async Task<IActionResult> Put(PrivacyDto dto)
    {
        var p = await _db.UserPrivacies.FirstOrDefaultAsync(x => x.UserId == UserId);
        if (p is null)
        {
            p = new UserPrivacy { UserId = UserId };
            _db.UserPrivacies.Add(p);
        }
        p.ShowStats = dto.ShowStats;
        p.ShowActivity = dto.ShowActivity;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}