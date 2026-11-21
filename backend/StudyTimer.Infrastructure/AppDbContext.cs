using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;

namespace StudyTimer.Infrastructure;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Subject> Subjects => Set<Subject>();
    public DbSet<StudySession> StudySessions => Set<StudySession>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Challenge> Challenges => Set<Challenge>();
    public DbSet<ChallengeParticipant> ChallengeParticipants => Set<ChallengeParticipant>();
    public DbSet<UserBadge> UserBadges => Set<UserBadge>();
    public DbSet<Friendship> Friendships => Set<Friendship>();
    public DbSet<UserPrivacy> UserPrivacies => Set<UserPrivacy>();
    public DbSet<ChallengeInvitation> ChallengeInvitations => Set<ChallengeInvitation>();
    public DbSet<AppNotification> Notifications => Set<AppNotification>();
    public DbSet<TaskItem> TaskItems => Set<TaskItem>();
    public DbSet<StudyRoom> StudyRooms => Set<StudyRoom>();
    public DbSet<RoomParticipant> RoomParticipants => Set<RoomParticipant>();
    public DbSet<RoomMessage> RoomMessages => Set<RoomMessage>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>().HasIndex(u => u.Email).IsUnique();
        b.Entity<User>().HasIndex(u => u.Username).IsUnique();
        b.Entity<StudySession>().HasIndex(s => new { s.UserId, s.StartedAtUtc });
        b.Entity<RefreshToken>().HasIndex(r => r.TokenHash).IsUnique();
        b.Entity<ChallengeParticipant>().HasKey(p => new { p.ChallengeId, p.UserId });
        b.Entity<Challenge>().HasIndex(c => c.EndsAtUtc);
        b.Entity<UserBadge>().HasIndex(x => new { x.UserId, x.Code }).IsUnique();
        b.Entity<Friendship>().HasIndex(f => new { f.RequesterId, f.AddresseeId }).IsUnique();
        b.Entity<UserPrivacy>().HasKey(p => p.UserId);
        b.Entity<ChallengeInvitation>().HasIndex(i => new { i.ChallengeId, i.InviteeId });
        b.Entity<AppNotification>().HasIndex(n => new { n.UserId, n.CreatedAtUtc });
        b.Entity<TaskItem>().HasIndex(t => new { t.UserId, t.DueAtUtc });
        b.Entity<StudyRoom>().HasIndex(r => r.Code).IsUnique();
        b.Entity<RoomParticipant>().HasKey(p => new { p.RoomId, p.UserId });
        b.Entity<RoomMessage>().HasIndex(m => new { m.RoomId, m.SentAtUtc });
    }
}
