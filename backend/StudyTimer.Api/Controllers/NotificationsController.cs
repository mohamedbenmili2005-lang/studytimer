using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

/// <summary>Aide pour creer une notification dans la meme transaction que l'action qui la declenche.</summary>
public static class Notifier
{
    public static void Add(AppDbContext db, Guid userId, string type, string title, string body) =>
        db.Notifications.Add(new AppNotification { UserId = userId, Type = type, Title = title, Body = body });
}

[ApiController, Authorize]
[Route("api/notifications")]
public class NotificationsController : ControllerBase
{
    private readonly AppDbContext _db;
    public NotificationsController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var items = await _db.Notifications.AsNoTracking()
            .Where(n => n.UserId == UserId)
            .OrderByDescending(n => n.CreatedAtUtc).Take(50)
            .Select(n => new { n.Id, n.Type, n.Title, n.Body, n.CreatedAtUtc, Read = n.ReadAtUtc != null })
            .ToListAsync();
        var unread = await _db.Notifications.CountAsync(n => n.UserId == UserId && n.ReadAtUtc == null);
        return Ok(new { Unread = unread, Items = items });
    }

    [HttpPost("{id:guid}/read")]
    public async Task<IActionResult> Read(Guid id)
    {
        var n = await _db.Notifications.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (n is null) return NotFound();
        n.ReadAtUtc ??= DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("read-all")]
    public async Task<IActionResult> ReadAll()
    {
        var rows = await _db.Notifications.Where(n => n.UserId == UserId && n.ReadAtUtc == null).ToListAsync();
        foreach (var n in rows) n.ReadAtUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}