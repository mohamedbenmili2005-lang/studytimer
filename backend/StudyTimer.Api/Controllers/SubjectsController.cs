using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record CreateSubjectDto(string Name, string? Color);

[ApiController, Authorize]
[Route("api/subjects")]
public class SubjectsController : ControllerBase
{
    private readonly AppDbContext _db;
    public SubjectsController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet]
    public async Task<IActionResult> List() =>
        Ok(await _db.Subjects.AsNoTracking()
            .Where(s => s.UserId == UserId)
            .OrderBy(s => s.Name)
            .Select(s => new { s.Id, s.Name, s.Color })
            .ToListAsync());

    [HttpPost]
    public async Task<IActionResult> Create(CreateSubjectDto dto)
    {
        var name = (dto.Name ?? "").Trim();
        if (name.Length is < 1 or > 60)
            return BadRequest("Nom de matière invalide (1 à 60 caractères).");

        var existing = await _db.Subjects.AsNoTracking()
            .FirstOrDefaultAsync(s => s.UserId == UserId && s.Name.ToLower() == name.ToLower());
        if (existing is not null)
            return Ok(new { existing.Id, existing.Name, existing.Color });

        var subject = new Subject { UserId = UserId, Name = name, Color = dto.Color };
        _db.Subjects.Add(subject);
        await _db.SaveChangesAsync();
        return Ok(new { subject.Id, subject.Name, subject.Color });
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var s = await _db.Subjects.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (s is null) return NotFound();
        await _db.StudySessions.Where(x => x.UserId == UserId && x.SubjectId == id)
            .ExecuteUpdateAsync(u => u.SetProperty(x => x.SubjectId, (Guid?)null));
        _db.Subjects.Remove(s);
        await _db.SaveChangesAsync();
        return NoContent();
    }
}
