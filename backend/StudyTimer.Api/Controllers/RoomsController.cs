using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Api.Hubs;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record CreateRoomDto(string Name, bool IsPublic = true);
public record JoinRoomDto(string Code);
public record SendMessageDto(string Text);

/// <summary>Module 7 : salles d'etude collaboratives (publiques, privees, par code) + chat.</summary>
[ApiController, Authorize]
[Route("api/rooms")]
public class RoomsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<StudyHub> _hub;
    public RoomsController(AppDbContext db, IHubContext<StudyHub> hub) { _db = db; _hub = hub; }

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    private static DateTime Utc(DateTime d) =>
        d.Kind == DateTimeKind.Utc ? d
        : d.Kind == DateTimeKind.Local ? d.ToUniversalTime()
        : DateTime.SpecifyKind(d, DateTimeKind.Utc);

    private static string NewCode()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var chars = new char[6];
        for (int i = 0; i < chars.Length; i++)
            chars[i] = alphabet[System.Security.Cryptography.RandomNumberGenerator.GetInt32(alphabet.Length)];
        return new string(chars);
    }

    private Task<bool> IsMember(Guid roomId) =>
        _db.RoomParticipants.AnyAsync(p => p.RoomId == roomId && p.UserId == UserId);

    [HttpPost]
    public async Task<IActionResult> Create(CreateRoomDto dto)
    {
        var name = (dto.Name ?? "").Trim();
        if (name.Length == 0 || name.Length > 60) return BadRequest("Nom requis (60 caract\u00e8res max).");

        string code = NewCode();
        for (int i = 0; i < 5 && await _db.StudyRooms.AnyAsync(r => r.Code == code); i++) code = NewCode();

        var room = new StudyRoom { OwnerId = UserId, Name = name, IsPublic = dto.IsPublic, Code = code };
        _db.StudyRooms.Add(room);
        _db.RoomParticipants.Add(new RoomParticipant { RoomId = room.Id, UserId = UserId });
        await _db.SaveChangesAsync();
        return Ok(new { room.Id, room.Code });
    }

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var mine = await _db.RoomParticipants.AsNoTracking()
            .Where(p => p.UserId == UserId).Select(p => p.RoomId).ToListAsync();
        var rooms = await _db.StudyRooms.AsNoTracking()
            .Where(r => r.IsPublic || mine.Contains(r.Id))
            .OrderByDescending(r => r.CreatedAtUtc).Take(100).ToListAsync();
        var rids = rooms.Select(r => r.Id).ToList();
        var counts = await _db.RoomParticipants.AsNoTracking()
            .Where(p => rids.Contains(p.RoomId))
            .GroupBy(p => p.RoomId)
            .Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N);
        return Ok(rooms.Select(r => new
        {
            r.Id, r.Name, r.IsPublic,
            Participants = counts.GetValueOrDefault(r.Id),
            Joined = mine.Contains(r.Id)
        }));
    }

    /// <summary>Rejoindre par code (salle privee ou publique).</summary>
    [HttpPost("join")]
    public async Task<IActionResult> JoinByCode(JoinRoomDto dto)
    {
        var code = (dto.Code ?? "").Trim().ToUpperInvariant();
        var room = await _db.StudyRooms.AsNoTracking().FirstOrDefaultAsync(r => r.Code == code);
        if (room is null) return NotFound("Code inconnu.");
        if (!await IsMember(room.Id))
        {
            _db.RoomParticipants.Add(new RoomParticipant { RoomId = room.Id, UserId = UserId });
            await _db.SaveChangesAsync();
        }
        return Ok(new { room.Id, room.Name });
    }

    /// <summary>Rejoindre une salle publique.</summary>
    [HttpPost("{id:guid}/join")]
    public async Task<IActionResult> Join(Guid id)
    {
        var room = await _db.StudyRooms.AsNoTracking().FirstOrDefaultAsync(r => r.Id == id);
        if (room is null || (!room.IsPublic && !await IsMember(id))) return NotFound();
        if (!await IsMember(id))
        {
            _db.RoomParticipants.Add(new RoomParticipant { RoomId = id, UserId = UserId });
            await _db.SaveChangesAsync();
        }
        return NoContent();
    }

    [HttpPost("{id:guid}/leave")]
    public async Task<IActionResult> Leave(Guid id)
    {
        var p = await _db.RoomParticipants.FirstOrDefaultAsync(x => x.RoomId == id && x.UserId == UserId);
        if (p is null) return NotFound();
        _db.RoomParticipants.Remove(p);
        await _db.SaveChangesAsync();

        if (!await _db.RoomParticipants.AnyAsync(x => x.RoomId == id))
        {
            _db.RoomMessages.RemoveRange(_db.RoomMessages.Where(m => m.RoomId == id));
            _db.StudyRooms.RemoveRange(_db.StudyRooms.Where(r => r.Id == id));
            await _db.SaveChangesAsync();
        }
        return NoContent();
    }

    /// <summary>Detail d'une salle : participants, statut (Studying / Paused / Offline) et temps du jour.</summary>
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var room = await _db.StudyRooms.AsNoTracking().FirstOrDefaultAsync(r => r.Id == id);
        if (room is null) return NotFound();
        var ids = await _db.RoomParticipants.AsNoTracking()
            .Where(p => p.RoomId == id).Select(p => p.UserId).ToListAsync();
        if (!ids.Contains(UserId)) return Forbid();

        var names = await _db.Users.AsNoTracking().Where(u => ids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
        var active = await _db.StudySessions.AsNoTracking()
            .Where(s => ids.Contains(s.UserId) &&
                        (s.Status == SessionStatus.Running || s.Status == SessionStatus.Paused))
            .Select(s => new { s.UserId, s.Status }).ToListAsync();
        var dayStart = DateTime.UtcNow.Date;
        var today = await _db.StudySessions.AsNoTracking()
            .Where(s => ids.Contains(s.UserId) && s.Status == SessionStatus.Completed && s.StartedAtUtc >= dayStart)
            .GroupBy(s => s.UserId)
            .Select(g => new { UserId = g.Key, Seconds = g.Sum(x => x.AccumulatedSeconds) })
            .ToListAsync();

        var participants = ids.Select(uid => new
        {
            UserId = uid,
            Username = names.GetValueOrDefault(uid, "?"),
            Status = active.Any(a => a.UserId == uid && a.Status == SessionStatus.Running) ? "Studying"
                   : active.Any(a => a.UserId == uid) ? "Paused" : "Offline",
            TodaySeconds = today.Where(t => t.UserId == uid).Sum(t => t.Seconds)
        }).OrderBy(p => p.Username).ToList();

        return Ok(new { room.Id, room.Name, room.Code, room.IsPublic, IsOwner = room.OwnerId == UserId, Participants = participants });
    }

    [HttpGet("{id:guid}/messages")]
    public async Task<IActionResult> Messages(Guid id, [FromQuery] DateTime? after = null)
    {
        if (!await IsMember(id)) return Forbid();
        var q = _db.RoomMessages.AsNoTracking().Where(m => m.RoomId == id);
        if (after.HasValue) { var a = Utc(after.Value); q = q.Where(m => m.SentAtUtc > a); }
        var rows = await q.OrderByDescending(m => m.SentAtUtc).Take(100).ToListAsync();
        rows.Reverse();
        var uids = rows.Select(m => m.UserId).Distinct().ToList();
        var names = await _db.Users.AsNoTracking().Where(u => uids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
        return Ok(rows.Select(m => new
        {
            m.Id, m.UserId, Username = names.GetValueOrDefault(m.UserId, "?"), m.Text, m.SentAtUtc
        }));
    }

    [HttpPost("{id:guid}/messages")]
    public async Task<IActionResult> Send(Guid id, SendMessageDto dto)
    {
        if (!await IsMember(id)) return Forbid();
        var text = (dto.Text ?? "").Trim();
        if (text.Length is 0 or > 500) return BadRequest("Message : 1 \u00e0 500 caract\u00e8res.");

        var m = new RoomMessage { RoomId = id, UserId = UserId, Text = text };
        _db.RoomMessages.Add(m);
        await _db.SaveChangesAsync();

        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        var payload = new { m.Id, m.UserId, Username = me, m.Text, m.SentAtUtc };
        await _hub.Clients.Group($"room-{id}").SendAsync("message", payload);
        return Ok(payload);
    }
}