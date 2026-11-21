namespace StudyTimer.Domain.Entities;

/// <summary>Les 4 types de défis du cahier des charges.</summary>
public enum ChallengeType
{
    TotalTime,      // cumuler N secondes d'étude
    SessionCount,   // terminer N séances
    DailyStreak,    // N jours consécutifs (>= 10 min par jour)
    LongestSession  // réussir une séance d'au moins N secondes
}

public class Challenge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CreatorId { get; set; }
    public string Title { get; set; } = "";
    public ChallengeType Type { get; set; }
    public int Target { get; set; }               // secondes, séances ou jours selon le type
    public DateTime StartsAtUtc { get; set; }
    public DateTime EndsAtUtc { get; set; }
    public bool IsPublic { get; set; } = true;
    public List<ChallengeParticipant> Participants { get; set; } = new();
}

public class ChallengeParticipant
{
    public Guid ChallengeId { get; set; }
    public Challenge Challenge { get; set; } = null!;
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public DateTime JoinedAtUtc { get; set; } = DateTime.UtcNow;
}

public class UserBadge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Code { get; set; } = "";
    public DateTime EarnedAtUtc { get; set; } = DateTime.UtcNow;
}
