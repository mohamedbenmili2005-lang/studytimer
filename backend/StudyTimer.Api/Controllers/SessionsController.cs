
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/sessions")]
public class SessionsController : ControllerBase
{
    private readonly AppDbContext _db;

    public SessionsController(AppDbContext db)
    {
        _db = db;
    }

    private Guid UserId => Guid.Parse(
        User.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? User.FindFirstValue("sub")!
    );

    // Calcul du temps écoulé
    private static int GetElapsedSeconds(StudySession s)
    {
        int seconds = s.AccumulatedSeconds;

        if (s.Status == SessionStatus.Running)
        {
            var lastStart = s.LastResumedAtUtc ?? s.StartedAtUtc;
            seconds += Math.Max(0, (int)(DateTime.UtcNow - lastStart).TotalSeconds);
        }

        return seconds;
    }

    // Format de réponse envoyé à Flutter
    private static object ToResponse(StudySession s)
    {
        return new
        {
            s.Id,
            Mode = s.Mode.ToString(),
            Status = s.Status.ToString(),
            s.TargetSeconds,
            s.StartedAtUtc,
            s.EndedAtUtc,
            AccumulatedSeconds = s.AccumulatedSeconds,
            ElapsedSeconds = GetElapsedSeconds(s)
        };
    }

    // GET : séance actuelle
    [HttpGet("current")]
    public async Task<IActionResult> Current()
    {
        var session = await _db.StudySessions
            .AsNoTracking()
            .Where(s => s.UserId == UserId &&
                (s.Status == SessionStatus.Running ||
                 s.Status == SessionStatus.Paused))
            .OrderByDescending(s => s.StartedAtUtc)
            .FirstOrDefaultAsync();

        return Ok(session == null ? null : ToResponse(session));
    }

    // POST : démarrer une séance
    [HttpPost("start")]
    public async Task<IActionResult> Start([FromBody] StartSessionRequest request)
    {
        if (!Enum.TryParse<SessionMode>(request.Mode, true, out var mode)
            || !Enum.IsDefined(typeof(SessionMode), mode))
        {
            return BadRequest(new { message = "Mode invalide." });
        }

        if (request.TargetSeconds.HasValue &&
            request.TargetSeconds.Value <= 0)
        {
            return BadRequest(new { message = "Durée invalide." });
        }

        var active = await _db.StudySessions.AnyAsync(s =>
            s.UserId == UserId &&
            (s.Status == SessionStatus.Running ||
             s.Status == SessionStatus.Paused));

        if (active)
        {
            return Conflict(new {
                message = "Une séance est déjà en cours."
            });
        }

        var now = DateTime.UtcNow;

        var session = new StudySession
        {
            UserId = UserId,
            Mode = mode,
            Status = SessionStatus.Running,
            TargetSeconds = request.TargetSeconds,
            StartedAtUtc = now,
            LastResumedAtUtc = now,
            AccumulatedSeconds = 0
        };

        _db.StudySessions.Add(session);
        await _db.SaveChangesAsync();

        return Ok(ToResponse(session));
    }

    // POST : mettre en pause
    [HttpPost("pause")]
    public async Task<IActionResult> Pause()
    {
        var session = await GetActiveSession();

        if (session == null)
            return NotFound(new { message = "Aucune séance active." });

        if (session.Status != SessionStatus.Running)
            return BadRequest(new { message = "La séance n'est pas en cours." });

        session.AccumulatedSeconds = GetElapsedSeconds(session);
        session.Status = SessionStatus.Paused;
        session.LastResumedAtUtc = null;

        await _db.SaveChangesAsync();

        return Ok(ToResponse(session));
    }

    // POST : reprendre
    [HttpPost("resume")]
    public async Task<IActionResult> Resume()
    {
        var session = await GetActiveSession();

        if (session == null)
            return NotFound(new { message = "Aucune séance active." });

        if (session.Status != SessionStatus.Paused)
            return BadRequest(new { message = "La séance n'est pas en pause." });

        session.Status = SessionStatus.Running;
        session.LastResumedAtUtc = DateTime.UtcNow;

        await _db.SaveChangesAsync();

        return Ok(ToResponse(session));
    }

    // POST : terminer la séance
    [HttpPost("stop")]
    public async Task<IActionResult> Stop()
    {
        var session = await GetActiveSession();

        if (session == null)
            return NotFound(new { message = "Aucune séance active." });

        if (session.Status == SessionStatus.Running)
        {
            session.AccumulatedSeconds = GetElapsedSeconds(session);
        }

        session.Status = SessionStatus.Completed;
        session.EndedAtUtc = DateTime.UtcNow;
        session.LastResumedAtUtc = null;

        await _db.SaveChangesAsync();

        return Ok(ToResponse(session));
    }

    // Récupérer la séance active de l'utilisateur
    private async Task<StudySession?> GetActiveSession()
    {
        return await _db.StudySessions
            .Where(s => s.UserId == UserId &&
                (s.Status == SessionStatus.Running ||
                 s.Status == SessionStatus.Paused))
            .OrderByDescending(s => s.StartedAtUtc)
            .FirstOrDefaultAsync();
    }
}

// Données reçues depuis Flutter
public class StartSessionRequest
{
    public string Mode { get; set; } = "Focus";
    public int? TargetSeconds { get; set; }
}
