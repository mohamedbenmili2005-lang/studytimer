using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record RegisterDto(string FirstName, string LastName, string Username,
                          string Email, string Password, string? Country, string? TimeZone);
public record LoginDto(string Email, string Password);
public record RefreshDto(string RefreshToken);

[ApiController]
[EnableRateLimiting("auth")]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _cfg;
    private readonly PasswordHasher<User> _hasher = new();

    public AuthController(AppDbContext db, IConfiguration cfg) { _db = db; _cfg = cfg; }

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Email) || !dto.Email.Contains('@'))
            return BadRequest("Email invalide.");
        if (string.IsNullOrWhiteSpace(dto.Username) || dto.Username.Trim().Length is < 3 or > 30)
            return BadRequest("Pseudonyme invalide (3 à 30 caractères).");
        if (string.IsNullOrWhiteSpace(dto.FirstName) || string.IsNullOrWhiteSpace(dto.LastName))
            return BadRequest("Prénom et nom requis.");
        if (dto.Password is null || dto.Password.Length < 8) return BadRequest("Mot de passe trop court (8 min).");
        var email = dto.Email.Trim().ToLowerInvariant();
        if (await _db.Users.AnyAsync(u => u.Email == email || u.Username == dto.Username))
            return Conflict("Email ou pseudonyme déjà utilisé.");

        var user = new User
        {
            Email = email,
            Username = dto.Username,
            FirstName = dto.FirstName,
            LastName = dto.LastName,
            Country = dto.Country,
            TimeZone = dto.TimeZone ?? "UTC"
        };
        user.PasswordHash = _hasher.HashPassword(user, dto.Password);
        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        return Ok(await Issue(user));
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginDto dto)
    {
        var email = dto.Email.Trim().ToLowerInvariant();
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (user is null) return Unauthorized("Identifiants invalides.");

        var result = _hasher.VerifyHashedPassword(user, user.PasswordHash, dto.Password);
        if (result == PasswordVerificationResult.Failed) return Unauthorized("Identifiants invalides.");

        return Ok(await Issue(user));
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh(RefreshDto dto)
    {
        var hash = Hash(dto.RefreshToken);
        var rt = await _db.RefreshTokens.Include(r => r.User)
                    .FirstOrDefaultAsync(r => r.TokenHash == hash);
        if (rt is null || rt.RevokedAtUtc is not null || rt.ExpiresAtUtc < DateTime.UtcNow)
            return Unauthorized("Session expirée.");

        rt.RevokedAtUtc = DateTime.UtcNow;      // rotation : un refresh token ne sert qu'une fois
        return Ok(await Issue(rt.User));        // Issue enregistre aussi la révocation
    }

    private async Task<object> Issue(User user)
    {
        var raw = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        _db.RefreshTokens.Add(new RefreshToken
        {
            UserId = user.Id,
            TokenHash = Hash(raw),
            ExpiresAtUtc = DateTime.UtcNow.AddDays(30)
        });
        await _db.SaveChangesAsync();
        return new { token = CreateToken(user), refreshToken = raw };
    }

    private static string Hash(string s) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s)));

    private string CreateToken(User user)
    {
        var jwt = _cfg.GetSection("Jwt");
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!));
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new Claim(JwtRegisteredClaimNames.Email, user.Email),
            new Claim("username", user.Username)
        };
        var token = new JwtSecurityToken(
            issuer: jwt["Issuer"], audience: jwt["Audience"], claims: claims,
            expires: DateTime.UtcNow.AddMinutes(int.Parse(jwt["ExpireMinutes"]!)),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
