namespace StudyTimer.Domain.Entities;

public enum TaskPriority { Low, Medium, High }

/// <summary>Tache du planificateur d'etude.</summary>
public class TaskItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid? SubjectId { get; set; }
    public string Title { get; set; } = "";
    public DateTime? DueAtUtc { get; set; }
    public int? EstimatedMinutes { get; set; }
    public TaskPriority Priority { get; set; } = TaskPriority.Medium;
    public bool IsDone { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}