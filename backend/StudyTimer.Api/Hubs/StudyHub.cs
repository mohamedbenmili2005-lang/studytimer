using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Hubs;

/// <summary>Temps reel (cahier 5.1) : les clients rejoignent le groupe d'une salle pour recevoir les messages.</summary>
[Authorize]
public class StudyHub : Hub
{
    private readonly AppDbContext _db;
    public StudyHub(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(Context.User!.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? Context.User!.FindFirstValue("sub")!);

    public async Task JoinRoom(Guid roomId)
    {
        var uid = UserId;
        if (!await _db.RoomParticipants.AnyAsync(p => p.RoomId == roomId && p.UserId == uid))
            throw new HubException("Vous n'etes pas membre de cette salle.");
        await Groups.AddToGroupAsync(Context.ConnectionId, $"room-{roomId}");
    }

    public Task LeaveRoom(Guid roomId) =>
        Groups.RemoveFromGroupAsync(Context.ConnectionId, $"room-{roomId}");
}