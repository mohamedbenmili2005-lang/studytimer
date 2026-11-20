namespace StudyTimer.Domain.Entities;

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Email { get; set; } = "";
    public string Username { get; set; } = "";
    public string FirstName { get; set; } = "";
    public string LastName { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public string? Country { get; set; }
    public string TimeZone { get; set; } = "UTC";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public List<StudySession> Sessions { get; set; } = new();
}
