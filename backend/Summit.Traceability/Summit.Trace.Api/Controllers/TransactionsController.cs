using Microsoft.AspNetCore.Mvc;

namespace Summit.Trace.Api.Controllers;

[ApiController]
[Route("api/tx")]
public class TransactionsController : ControllerBase
{
    [HttpPost("receive")]
    public IActionResult Receive() => StatusCode(501, new { message = "Implement in step 6 (Transaction endpoints)." });

    [HttpPost("move")]
    public IActionResult Move() => StatusCode(501, new { message = "Implement in step 6 (Transaction endpoints)." });

    [HttpPost("consume")]
    public IActionResult Consume() => StatusCode(501, new { message = "Implement in step 6 (Transaction endpoints)." });
}