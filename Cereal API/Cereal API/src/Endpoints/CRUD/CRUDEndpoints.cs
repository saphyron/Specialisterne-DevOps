// src/Endpoints/CRUD/CRUDEndpoints.cs
using CerealAPI.Models;
using Dapper;

namespace CerealAPI.Endpoints.CRUD
{
    /// <summary>
    /// Registrerer CRUD-endpoints til tabellen <c>dbo.Cereal</c> under ruten <c>/cereals</c>.
    /// Indeholder read-only forespørgsler (GET) og skriveoperationer (POST/PUT/DELETE) beskyttet af politikken <c>WriteOps</c>.
    /// </summary>
    /// <remarks>
    /// Minimal API handlers binder automatisk parametre fra DI (f.eks. <c>SqlConnectionCeral</c>), route (<c>{take}</c>, <c>{name}</c> osv.)
    /// og body (JSON til <see cref="Cereal"/>). Dapper bruges med parametre for at undgå SQL injection.
    /// </remarks>
    public static class CRUDEndpoints
    {
        /// <summary>
        /// Mapper alle <c>/cereals</c>-endpoints på den angivne route-builder.
        /// </summary>
        /// <param name="app">Den route-builder (f.eks. <see cref="WebApplication"/>) der skal have endpoints tilføjet.</param>
        /// <returns>Samme route-builder, så kald kan kædes.</returns>
        /// <remarks>
        /// Læseendpoints er åbne; skriveendpoints kræver <c>.RequireAuthorization("WriteOps")</c>.
        /// </remarks>
        public static IEndpointRouteBuilder MapCrudEndpoints(this IEndpointRouteBuilder app)
        {
            var group = app.MapGroup("/cereals");

            // GET /cereals — hent alle rækker ordnet efter navn (letvægtsliste)
            group.MapGet("", async (CerealAPI.Data.SqlConnectionCeral cereal) =>
            {
                var sql = @"SELECT *
                            FROM dbo.Cereal
                            ORDER BY name";
                using var conn = cereal.Create();
                var rows = await conn.QueryAsync<Cereal>(sql, new { });
                return Results.Ok(rows);
            })
            .WithSummary("Hent alle cereals")
            .WithDescription("Returnerer alle rækker fra dbo.Cereal i navneorden.");
            // GET /cereals/top/{take}  — hent top N rækker; defensiv validering af 'take'
            group.MapGet("/top/{take:int}", async (int take, CerealAPI.Data.SqlConnectionCeral cereal) =>
            {
                // defensiv validering (undgå minus/0 og urimeligt høje værdier)
                if (take < 1) take = 1;
                if (take > 10000) take = 10000; // juster grænsen efter behov

                const string sql = @"
                    SELECT TOP (@Take) *
                    FROM dbo.Cereal
                    ORDER BY name;";

                using var conn = cereal.Create();
                var rows = await conn.QueryAsync<Cereal>(sql, new { Take = take });
                return Results.Ok(rows);
            })
            .WithSummary("Hent top N cereals")
            .WithDescription("Returnerer de første N rækker fra dbo.Cereal i navneorden. Bruges som letvægtsliste.");

            // POST /cereals  — indsæt ny række (kræver WriteOps)
            group.MapPost("", async (Cereal cereal, CerealAPI.Data.SqlConnectionCeral cereals) =>
            {
                const string sql = @"
                    INSERT INTO dbo.Cereal
                    (name,mfr,type,calories,protein,fat,sodium,fiber,carbo,sugars,potass,vitamins,shelf,weight,cups,rating)
                    VALUES
                    (@name,@mfr,@type,@calories,@protein,@fat,@sodium,@fiber,@carbo,@sugars,
                    @potass,@vitamins,@shelf,@weight,@cups,@rating);";
                using var conn = cereals.Create();
                var affected = await conn.ExecuteAsync(sql, cereal);
                return Results.Ok(new { inserted = affected });
            }).RequireAuthorization("WriteOps");

            // PUT /cereals/{name}/{mfr}/{type} — opdater eksisterende række ud fra kompositnøgle (kræver WriteOps)
            // Navne som "100% Bran" skal URL-encodes: /cereals/100%25%20Bran/K/C
            group.MapPut("/{name}/{mfr}/{type}", async (string name, string mfr, string type, Cereal update, CerealAPI.Data.SqlConnectionCeral cereals) =>
            {
                const string sql = @"
                    UPDATE dbo.Cereal
                    SET
                        calories = @calories,
                        protein  = @protein,
                        fat      = @fat,
                        sodium   = @sodium,
                        fiber    = @fiber,
                        carbo    = @carbo,
                        sugars   = @sugars,
                        potass   = @potass,
                        vitamins = @vitamins,
                        shelf    = @shelf,
                        weight   = @weight,
                        cups     = @cups,
                        rating   = @rating
                    WHERE name = @key_name AND mfr = @key_mfr AND type = @key_type;";

                using var conn = cereals.Create();
                var affected = await conn.ExecuteAsync(sql, new
                {
                    key_name = name,
                    key_mfr = mfr,
                    key_type = type,
                    update.calories,
                    update.protein,
                    update.fat,
                    update.sodium,
                    update.fiber,
                    update.carbo,
                    update.sugars,
                    update.potass,
                    update.vitamins,
                    update.shelf,
                    update.weight,
                    update.cups,
                    update.rating
                });
                // Returnér 404 hvis ingen rækker blev ramt
                return affected == 0 ? Results.NotFound(new { message = "Row not found." })
                                     : Results.Ok(new { updated = affected });
            }).RequireAuthorization("WriteOps");

            // DELETE /cereals/{name}/{mfr}/{type} — slet række ud fra kompositnøgle (kræver WriteOps)
            group.MapDelete("/{name}/{mfr}/{type}", async (string name, string mfr, string type, CerealAPI.Data.SqlConnectionCeral cereals) =>
            {
                const string sql = @"DELETE FROM dbo.Cereal WHERE name=@name AND mfr=@mfr AND type=@type;";
                using var conn = cereals.Create();
                var affected = await conn.ExecuteAsync(sql, new { name, mfr, type });
                // Returnér 404 hvis ingen rækker blev slettet
                return affected == 0 ? Results.NotFound(new { message = "Row not found." })
                                     : Results.Ok(new { deleted = affected });
            }).RequireAuthorization("WriteOps");

            return app;
        }
    }
}
