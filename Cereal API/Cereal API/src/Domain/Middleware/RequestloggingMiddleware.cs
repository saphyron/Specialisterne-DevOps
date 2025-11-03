// src/Middleware/RequestLoggingMiddleware.cs

/// <summary>
/// Logger hver HTTP-request med metode, sti, statuskode og varighed.
/// Hjælper med at få overblik over trafikken og fejl i applikationen.
/// </summary>
/// <remarks>
/// Måler varighed med en <c>Stopwatch</c>, lader requesten gå videre i pipeline
/// og logger et Information-entry ved succes samt et Error-entry ved exceptions.
/// Middleware genkaster exception efter logging, så korrekt fejlhåndtering/HTTP-svar
/// bevares længere oppe i pipeline.
/// </remarks>
public sealed class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _log;
    /// <summary>
    /// Opretter middleware, som kan logge ind/udgående requests.
    /// </summary>
    /// <param name="next">Den næste middleware/delegate i ASP.NET Core pipeline.</param>
    /// <param name="log">Logger instans til at skrive hændelser.</param>
    public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> log)
    { _next = next; _log = log; }
    /// <summary>
    /// Behandler en indkommende HTTP-request og logger resultatet.
    /// </summary>
    /// <param name="ctx">Den aktuelle <see cref="HttpContext"/>.</param>
    /// <returns>En <see cref="Task"/> der fuldføres, når den næste middleware er kørt.</returns>
    /// <remarks>
    /// Logger på niveau Information ved succes (med statuskode) og Error ved exception.
    /// Varigheden logges i millisekunder. Exceptions genkastes.
    /// </remarks>
    public async Task Invoke(HttpContext ctx)
    {
        // Start målingen for den aktuelle request
        var sw = System.Diagnostics.Stopwatch.StartNew();

        // Læs basis-oplysninger til log
        var path = ctx.Request.Path;
        var query = ctx.Request.QueryString.Value ?? "";
        var method = ctx.Request.Method;

        try
        {
            // Lad requesten fortsætte til næste middleware/endpoint
            await _next(ctx);

            // Succes: stop måling og skriv Info-log
            sw.Stop();
            _log.LogInformation("HTTP {Method} {Path}{Query} -> {Status} in {Elapsed} ms",
                method, path, query, ctx.Response?.StatusCode, sw.ElapsedMilliseconds);
        }
        catch (Exception ex)
        {
            // Fejl: stop måling, skriv Error-log og genkast
            sw.Stop();
            _log.LogError(ex, "HTTP {Method} {Path}{Query} failed in {Elapsed} ms",
                method, path, query, sw.ElapsedMilliseconds);
            throw;
        }
    }
}
