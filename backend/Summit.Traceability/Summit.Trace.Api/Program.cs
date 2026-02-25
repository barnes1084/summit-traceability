using Microsoft.EntityFrameworkCore;
using Summit.Trace.Api.Data;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// Controllers + Swagger
builder.Services
  .AddControllers()
  .AddJsonOptions(o =>
  {
      o.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
      o.JsonSerializerOptions.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase;
  });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// EF Core (Postgres)
var connStr =
    builder.Configuration.GetConnectionString("Db")
    ?? throw new InvalidOperationException("Missing ConnectionStrings:Db");

builder.Services.AddDbContext<AppDbContext>(opt =>
{
    opt.UseNpgsql(connStr);
    // Helpful during early dev; remove later if you want:
    opt.EnableSensitiveDataLogging(builder.Environment.IsDevelopment());
});

// CORS (dev-friendly; tighten later)
builder.Services.AddCors(options =>
{
    options.AddPolicy("dev", p =>
        p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

var app = builder.Build();

app.UseCors("dev");

//if (app.Environment.IsDevelopment()) { app.UseSwagger(); app.UseSwaggerUI(); }
app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();
app.MapControllers();

app.Run();
