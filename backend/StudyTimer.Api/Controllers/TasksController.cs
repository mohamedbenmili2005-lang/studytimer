using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record TaskDto(string Title, Guid? SubjectId, DateTime? DueAtUtc, int? EstimatedMinutes, string? Priority);

/// <summary>Module 8 : planificateur d'etude.</summary>
[ApiController, Authorize]
[Route("api/tasks")]
public class TasksController : ControllerBase
{
    private readonly AppDbContext _db;
    public TasksController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    private static DateTime Utc(DateTime d) =>
        d.Kind == DateTimeKind.Utc ? d
        : d.Kind == DateTimeKind.Local ? d.ToUniversalTime()
        : DateTime.SpecifyKind(d, DateTimeKind.Utc);

    private static object Map(TaskItem t, DateTime now) => new
    {
        t.Id, t.Title, t.SubjectId, t.DueAtUtc, t.EstimatedMinutes,
        Priority = t.Priority.ToString(), t.IsDone, t.CompletedAtUtc,
        Overdue = !t.IsDone && t.DueAtUtc != null && t.DueAtUtc < now
    };

    private async Task<string?> Apply(TaskItem t, TaskDto dto)
    {
        var title = (dto.Title ?? "").Trim();
        if (title.Length == 0 || title.Length > 120) return "Titre requis (120 caract\u00e8res max).";
        if (dto.EstimatedMinutes is < 1 or > 1440) return "Dur\u00e9e estim\u00e9e : 1 \u00e0 1440 minutes.";
        var priority = TaskPriority.Medium;
        if (!string.IsNullOrWhiteSpace(dto.Priority) && !Enum.TryParse(dto.Priority, true, out priority))
            return "Priorit\u00e9 invalide (Low, Medium, High).";
        if (dto.SubjectId.HasValue &&
            !await _db.Subjects.AnyAsync(s => s.Id == dto.SubjectId && s.UserId == UserId))
            return "Mati\u00e8re inconnue.";

        t.Title = title;
        t.SubjectId = dto.SubjectId;
        t.DueAtUtc = dto.DueAtUtc.HasValue ? Utc(dto.DueAtUtc.Value) : null;
        t.EstimatedMinutes = dto.EstimatedMinutes;
        t.Priority = priority;
        return null;
    }

    [HttpPost]
    public async Task<IActionResult> Create(TaskDto dto)
    {
        var t = new TaskItem { UserId = UserId };
        var error = await Apply(t, dto);
        if (error is not null) return BadRequest(error);
        _db.TaskItems.Add(t);
        await _db.SaveChangesAsync();
        return Ok(Map(t, DateTime.UtcNow));
    }

    /// <summary>status = all | open | done | overdue ; from/to filtrent sur l'echeance (calendrier).</summary>
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string status = "all",
        [FromQuery(Name = "from")] DateTime? fromUtc = null, [FromQuery(Name = "to")] DateTime? toUtc = null)
    {
        var now = DateTime.UtcNow;
        var q = _db.TaskItems.AsNoTracking().Where(t => t.UserId == UserId);
        q = status switch
        {
            "open" => q.Where(t => !t.IsDone),
            "done" => q.Where(t => t.IsDone),
            "overdue" => q.Where(t => !t.IsDone && t.DueAtUtc != null && t.DueAtUtc < now),
            _ => q
        };
        if (fromUtc.HasValue) { var f = Utc(fromUtc.Value); q = q.Where(t => t.DueAtUtc != null && t.DueAtUtc >= f); }
        if (toUtc.HasValue) { var e = Utc(toUtc.Value); q = q.Where(t => t.DueAtUtc != null && t.DueAtUtc <= e); }
        var items = await q.OrderBy(t => t.IsDone).ThenBy(t => t.DueAtUtc == null).ThenBy(t => t.DueAtUtc)
            .Take(300).ToListAsync();
        return Ok(items.Select(t => Map(t, now)));
    }

    [HttpGet("overdue")]
    public async Task<IActionResult> Overdue()
    {
        var now = DateTime.UtcNow;
        var items = await _db.TaskItems.AsNoTracking()
            .Where(t => t.UserId == UserId && !t.IsDone && t.DueAtUtc != null && t.DueAtUtc < now)
            .OrderBy(t => t.DueAtUtc).ToListAsync();
        return Ok(items.Select(t => Map(t, now)));
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, TaskDto dto)
    {
        var t = await _db.TaskItems.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (t is null) return NotFound();
        var error = await Apply(t, dto);
        if (error is not null) return BadRequest(error);
        await _db.SaveChangesAsync();
        return Ok(Map(t, DateTime.UtcNow));
    }

    [HttpPost("{id:guid}/complete")]
    public async Task<IActionResult> Complete(Guid id)
    {
        var t = await _db.TaskItems.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (t is null) return NotFound();
        if (!t.IsDone)
        {
            t.IsDone = true;
            t.CompletedAtUtc = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }
        return Ok(Map(t, DateTime.UtcNow));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var t = await _db.TaskItems.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (t is null) return NotFound();
        _db.TaskItems.Remove(t);
        await _db.SaveChangesAsync();
        return NoContent();
    }
}