using Microsoft.AspNetCore.Mvc;
using Summit.Trace.Api.Data;
using Summit.Trace.Api.Data.Entities;

namespace Summit.Trace.Api.Controllers;

public record CreateScanEventRequest(
    string Data,
    string? Symbology,
    string SourceMode,
    string? Vendor,
    string? DeviceId,
    Guid? SiteId,
    Guid? StationId,
    Guid? UserId,
    string? Screen,
    string? ExpectedType,
    string? RawJson
);

[ApiController]
[Route("api/scan-events")]
public class ScanEventsController : ControllerBase
{
    private readonly AppDbContext _db;

    public ScanEventsController(AppDbContext db) => _db = db;

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateScanEventRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Data))
            return BadRequest(new { message = "Data is required" });

        var e = new ScanEvent
        {
            event_id = Guid.NewGuid(),
            ts = DateTimeOffset.UtcNow,
            data = req.Data.Trim(),
            symbology = req.Symbology,
            source_mode = string.IsNullOrWhiteSpace(req.SourceMode) ? "unknown" : req.SourceMode,
            vendor = req.Vendor,
            device_id = req.DeviceId,
            site_id = req.SiteId,
            station_id = req.StationId,
            user_id = req.UserId,
            screen = req.Screen,
            expected_type = req.ExpectedType,
            raw_json = req.RawJson
        };

        _db.ScanEvents.Add(e);
        await _db.SaveChangesAsync();

        return Created($"/api/scan-events/{e.event_id}", new { e.event_id, e.ts });
    }
}