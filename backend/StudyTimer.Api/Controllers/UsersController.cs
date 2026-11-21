using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record UpdateProfileDto(string FirstName, string LastName, string? Country, string TimeZone);

[ApiController, Authorize]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly AppDbContext _db;
    public UsersController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet("profile")]
    public async Task<IActionResult> Profile()
    {
        var u = await _db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == UserId);
        return u is null ? NotFound() : Ok(new { u.Id, u.Username, u.FirstName, u.LastName, u.Email, u.Country, u.TimeZone });
    }

    [HttpPut("profile")]
    public async Task<IActionResult> Update(UpdateProfileDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.FirstName) || string.IsNullOrWhiteSpace(dto.LastName))
            return BadRequest("Prénom et nom requis.");
        try { TimeZoneInfo.FindSystemTimeZoneById(dto.TimeZone); }
        catch { return BadRequest("Fuseau horaire inconnu."); }

        var u = await _db.Users.FirstOrDefaultAsync(x => x.Id == UserId);
        if (u is null) return NotFound();
        u.FirstName = dto.FirstName.Trim();
        u.LastName = dto.LastName.Trim();
        u.Country = dto.Country;
        u.TimeZone = dto.TimeZone;
        await _db.SaveChangesAsync();
        return Ok(new { u.Id, u.Username, u.FirstName, u.LastName, u.Email, u.Country, u.TimeZone });
    }
}
