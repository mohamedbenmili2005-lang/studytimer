namespace StudyTimer.Domain.Entities;

public class StudyRoom
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerId { get; set; }
    public string Name { get; set; } = "";
    public bool IsPublic { get; set; } = true;
    public string Code { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public class RoomParticipant
{
    public Guid RoomId { get; set; }
    public Guid UserId { get; set; }
    public DateTime JoinedAtUtc { get; set; } = DateTime.UtcNow;
}

public class RoomMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RoomId { get; set; }
    public Guid UserId { get; set; }
    public string Text { get; set; } = "";
    public DateTime SentAtUtc { get; set; } = DateTime.UtcNow;
}