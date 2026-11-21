using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record ChallengeInviteDto(string Username);

/// <summary>Invitations aux defis (cahier module 3) ; RG06 : refusees apres la date limite.</summary>
[ApiController, Authorize]
[Route("api/challenges")]
public class ChallengeInvitesController : ControllerBase
{
    private readonly AppDbContext _db;
    public ChallengeInvitesController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpPost("{id:guid}/invite")]
    public async Task<IActionResult> Invite(Guid id, ChallengeInviteDto dto)
    {
        var c = await _db.Challenges.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (c is null) return NotFound();
        if (c.EndsAtUtc < DateTime.UtcNow) return BadRequest("Ce d\u00e9fi est termin\u00e9.");
        if (!await _db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == id && p.UserId == UserId)) return Forbid();

        var name = (dto.Username ?? "").Trim().ToLower();
        var target = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == name);
        if (target is null) return NotFound("Utilisateur introuvable.");
        if (await _db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == id && p.UserId == target.Id))
            return Conflict("D\u00e9j\u00e0 participant.");
        if (await _db.ChallengeInvitations.AnyAsync(i =>
                i.ChallengeId == id && i.InviteeId == target.Id && i.Status == RequestStatus.Pending))
            return Conflict("Invitation d\u00e9j\u00e0 envoy\u00e9e.");

        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        var inv = new ChallengeInvitation { ChallengeId = id, InviterId = UserId, InviteeId = target.Id };
        _db.ChallengeInvitations.Add(inv);
        Notifier.Add(_db, target.Id, "challenge_invite", "Invitation \u00e0 un d\u00e9fi", $"{me} vous invite au d\u00e9fi \u00ab {c.Title} \u00bb.");
        await _db.SaveChangesAsync();
        return Ok(new { inv.Id });
    }

    [HttpGet("invitations")]
    public async Task<IActionResult> Pending()
    {
        var rows = await _db.ChallengeInvitations.AsNoTracking()
            .Where(i => i.InviteeId == UserId && i.Status == RequestStatus.Pending)
            .OrderByDescending(i => i.CreatedAtUtc).ToListAsync();
        var cids = rows.Select(r => r.ChallengeId).Distinct().ToList();
        var titles = await _db.Challenges.AsNoTracking().Where(c => cids.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c.Title);
        var uids = rows.Select(r => r.InviterId).Distinct().ToList();
        var names = await _db.Users.AsNoTracking().Where(u => uids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
        return Ok(rows.Select(r => new
        {
            r.Id, r.ChallengeId,
            Title = titles.GetValueOrDefault(r.ChallengeId, "?"),
            Inviter = names.GetValueOrDefault(r.InviterId, "?"),
            r.CreatedAtUtc
        }));
    }

    [HttpPost("invitations/{invId:guid}/accept")]
    public async Task<IActionResult> Accept(Guid invId)
    {
        var inv = await _db.ChallengeInvitations.FirstOrDefaultAsync(i =>
            i.Id == invId && i.InviteeId == UserId && i.Status == RequestStatus.Pending);
        if (inv is null) return NotFound();

        var c = await _db.Challenges.AsNoTracking().FirstOrDefaultAsync(x => x.Id == inv.ChallengeId);
        if (c is null || c.EndsAtUtc < DateTime.UtcNow)
        {
            inv.Status = RequestStatus.Declined;
            await _db.SaveChangesAsync();
            return BadRequest("Ce d\u00e9fi est termin\u00e9.");
        }

        inv.Status = RequestStatus.Accepted;
        if (!await _db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == inv.ChallengeId && p.UserId == UserId))
            _db.ChallengeParticipants.Add(new ChallengeParticipant { ChallengeId = inv.ChallengeId, UserId = UserId });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("invitations/{invId:guid}/decline")]
    public async Task<IActionResult> Decline(Guid invId)
    {
        var inv = await _db.ChallengeInvitations.FirstOrDefaultAsync(i =>
            i.Id == invId && i.InviteeId == UserId && i.Status == RequestStatus.Pending);
        if (inv is null) return NotFound();
        inv.Status = RequestStatus.Declined;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}