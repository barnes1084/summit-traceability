using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Summit.Trace.Api.Data;

namespace Summit.Trace.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class HealthController : ControllerBase
{
    private readonly IConfiguration _config;
    private readonly AppDbContext _db;

    public HealthController(IConfiguration config, AppDbContext db)
    {
        _config = config;
        _db = db;
    }

    [HttpGet]
    public IActionResult Get()
        => Ok(new { status = "ok" });

    [HttpGet("version")]
    public IActionResult Version()
    => Ok(new
    {
        version = _config["Api:Version"] ?? "dev",
        environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Unknown"
    });

    [HttpGet("db")]
    public async Task<IActionResult> Database()
    {
        try
        {
            var canConnect = await _db.Database.CanConnectAsync();
            if (!canConnect)
                return StatusCode(500, new { status = "db_unreachable" });

            await using var conn = _db.Database.GetDbConnection();
            await conn.OpenAsync();

            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT version(), current_database(), now()";

            await using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();

            var version = reader.GetString(0);
            var dbName = reader.GetString(1);
            var serverTime = reader.GetDateTime(2);

            return Ok(new
            {
                status = "db_ok",
                database = dbName,
                serverTime,
                postgresVersion = version
            });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { status = "db_error", error = ex.Message });
        }
    }
}