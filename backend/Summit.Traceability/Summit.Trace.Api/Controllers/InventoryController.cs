using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Summit.Trace.Api.Data;

namespace Summit.Trace.Api.Controllers;

[ApiController]
[Route("api/inventory")]
public class InventoryController : ControllerBase
{
    private readonly AppDbContext _db;

    public InventoryController(AppDbContext db) => _db = db;

    [HttpGet("on-hand")]
    public async Task<IActionResult> OnHand([FromQuery] string siteCode)
    {
        var rows = await _db.InventoryOnHand
            .Where(x => x.SiteCode == siteCode)
            .OrderBy(x => x.LocationCode)
            .ThenBy(x => x.ItemCode)
            .ThenBy(x => x.LotCode)
            .ToListAsync();

        return Ok(rows);
    }
}