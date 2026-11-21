namespace StudyTimer.Domain.Entities;

public enum RequestStatus { Pending, Accepted, Declined }

/// <summary>Relation d'amitie (demande puis acceptation).</summary>
public class Friendship
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RequesterId { get; set; }
    public Guid AddresseeId { get; set; }
    public RequestStatus Status { get; set; } = RequestStatus.Pending;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

/// <summary>RG07 : ce que l'utilisateur laisse voir a ses amis.</summary>
public class UserPrivacy
{
    public Guid UserId { get; set; }
    public bool ShowStats { get; set; } = true;
    public bool ShowActivity { get; set; } = true;
}

public class ChallengeInvitation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ChallengeId { get; set; }
    public Guid InviterId { get; set; }
    public Guid InviteeId { get; set; }
    public RequestStatus Status { get; set; } = RequestStatus.Pending;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

/// <summary>Notification applicative (centre de notifications de l'application).</summary>
public class AppNotification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Type { get; set; } = "";
    public string Title { get; set; } = "";
    public string Body { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime? ReadAtUtc { get; set; }
}