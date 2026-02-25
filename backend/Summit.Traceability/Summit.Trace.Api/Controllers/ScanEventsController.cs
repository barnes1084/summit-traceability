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
            EventId = Guid.NewGuid(),
            Ts = DateTimeOffset.UtcNow,
            Data = req.Data.Trim(),
            Symbology = req.Symbology,
            SourceMode = string.IsNullOrWhiteSpace(req.SourceMode) ? "unknown" : req.SourceMode,
            Vendor = req.Vendor,
            DeviceId = req.DeviceId,
            SiteId = req.SiteId,
            StationId = req.StationId,
            UserId = req.UserId,
            Screen = req.Screen,
            ExpectedType = req.ExpectedType,
            RawJson = req.RawJson
        };

        _db.ScanEvents.Add(e);
        await _db.SaveChangesAsync();

        return Created($"/api/scan-events/{e.EventId}", new { e.EventId, e.Ts });
    }
}