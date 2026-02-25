using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Summit.Trace.Api.Data;

namespace Summit.Trace.Api.Controllers;

[ApiController]
[Route("api/master")]
public class MasterDataController : ControllerBase
{
    private readonly AppDbContext _db;

    public MasterDataController(AppDbContext db) => _db = db;

    [HttpGet("sites")]
    public async Task<IActionResult> Sites()
        => Ok(await _db.Sites.OrderBy(s => s.SiteCode).ToListAsync());

    [HttpGet("locations")]
    public async Task<IActionResult> Locations([FromQuery] string siteCode)
    {
        var siteId = await _db.Sites.Where(s => s.SiteCode == siteCode).Select(s => s.SiteId).FirstOrDefaultAsync();
        if (siteId == Guid.Empty) return NotFound(new { message = $"Unknown siteCode '{siteCode}'" });

        var rows = await _db.Locations
            .Where(l => l.SiteId == siteId && l.IsActive)
            .OrderBy(l => l.LocationCode)
            .ToListAsync();

        return Ok(rows);
    }

    [HttpGet("items")]
    public async Task<IActionResult> Items([FromQuery] string siteCode)
    {
        var siteId = await _db.Sites.Where(s => s.SiteCode == siteCode).Select(s => s.SiteId).FirstOrDefaultAsync();
        if (siteId == Guid.Empty) return NotFound(new { message = $"Unknown siteCode '{siteCode}'" });

        var rows = await _db.Items
            .Where(i => i.SiteId == siteId && i.IsActive)
            .OrderBy(i => i.ItemCode)
            .ToListAsync();

        return Ok(rows);
    }

    [HttpGet("workorders")]
    public async Task<IActionResult> WorkOrders([FromQuery] string siteCode, [FromQuery] string? status = "open")
    {
        var siteId = await _db.Sites.Where(s => s.SiteCode == siteCode).Select(s => s.SiteId).FirstOrDefaultAsync();
        if (siteId == Guid.Empty) return NotFound(new { message = $"Unknown siteCode '{siteCode}'" });

        var q = _db.WorkOrders.Where(w => w.SiteId == siteId);
        if (!string.IsNullOrWhiteSpace(status))
            q = q.Where(w => w.Status == status);

        return Ok(await q.OrderByDescending(w => w.CreatedAt).Take(200).ToListAsync());
    }

    [HttpGet("lots")]
    public async Task<IActionResult> Lots([FromQuery] string siteCode, [FromQuery] string? status = "active")
    {
        var siteId = await _db.Sites.Where(s => s.SiteCode == siteCode).Select(s => s.SiteId).FirstOrDefaultAsync();
        if (siteId == Guid.Empty) return NotFound(new { message = $"Unknown siteCode '{siteCode}'" });

        var q = _db.Lots.Where(l => l.SiteId == siteId);
        if (!string.IsNullOrWhiteSpace(status))
            q = q.Where(l => l.Status == status);

        return Ok(await q.OrderByDescending(l => l.CreatedAt).Take(200).ToListAsync());
    }
}