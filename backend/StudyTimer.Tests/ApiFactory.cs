using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using StudyTimer.Infrastructure;

namespace StudyTimer.Tests;

/// <summary>API rÃ©elle en mÃ©moire : base InMemory, secrets de test.</summary>
public class ApiFactory : WebApplicationFactory<Program>
{
    static ApiFactory()
    {
        Environment.SetEnvironmentVariable("Jwt__Key", "cle-de-test-uniquement-0123456789-abcdefghijklmnop");
        Environment.SetEnvironmentVariable("ConnectionStrings__Default", "Host=unused");
        Environment.SetEnvironmentVariable("Database__MigrateOnStart", "false");
        Environment.SetEnvironmentVariable("RateLimit__AuthPerMinute", "1000");
    }

    private readonly string _dbName = Guid.NewGuid().ToString();

    protected override void ConfigureWebHost(Microsoft.AspNetCore.Hosting.IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureServices(services =>
        {
            // Retire Npgsql, branche InMemory
            var toRemove = services.Where(d =>
                d.ServiceType == typeof(DbContextOptions<AppDbContext>) ||
                d.ServiceType == typeof(DbContextOptions) ||
                (d.ServiceType.IsGenericType &&
                 d.ServiceType.GetGenericArguments().Contains(typeof(AppDbContext)))).ToList();
            foreach (var d in toRemove) services.Remove(d);

            services.AddDbContext<AppDbContext>(o => o.UseInMemoryDatabase(_dbName));
        });
    }
}

