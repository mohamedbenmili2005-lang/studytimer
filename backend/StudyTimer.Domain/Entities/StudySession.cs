namespace StudyTimer.Domain.Entities;

public enum SessionMode { Focus, Pomodoro, Stopwatch }
public enum SessionStatus { Running, Paused, Completed, Rejected }

public class StudySession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public Guid? SubjectId { get; set; }
    public Guid? TaskId { get; set; }

    public SessionMode Mode { get; set; }
    public SessionStatus Status { get; set; } = SessionStatus.Running;
    public int? TargetSeconds { get; set; }

    public DateTime StartedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime? LastResumedAtUtc { get; set; }
    public DateTime? EndedAtUtc { get; set; }
    public int AccumulatedSeconds { get; set; }
    public int XpAwarded { get; set; }
}
