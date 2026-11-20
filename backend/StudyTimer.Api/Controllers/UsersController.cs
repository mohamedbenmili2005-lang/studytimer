using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

[ApiController, Authorize]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly AppDbContext _db;
    public UsersController(AppDbContext db) => _db = db;

    [HttpGet("profile")]
    public async Task<IActionResult> Profile()
    {
        var id = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                            ?? User.FindFirstValue("sub")!);
        var u = await _db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
        return u is null ? NotFound() : Ok(new { u.Id, u.Username, u.FirstName, u.LastName, u.Email, u.Country, u.TimeZone });
    }
}
