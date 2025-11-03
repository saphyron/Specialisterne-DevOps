// src/Endpoints/Ops/OpsEndpoints.cs
using System.Data;
using CerealAPI.Models;
using CerealAPI.Utils;
using Microsoft.Data.SqlClient;

namespace CerealAPI.Endpoints.Ops
{
    /// <summary>
    /// Ops-/værktøjsendpoints for bulkoperationer, CSV-import af cereals.
    /// </summary>
    /// <remarks>
    /// Registrerer et multipart upload-endpoint, som parser en semikolon-separeret CSV
    /// (med en 2. linje der beskriver datatyper) og indsætter data effektivt via
    /// <see cref="SqlBulkCopy"/> i tabellen <c>dbo.Cereal</c>.
    /// </remarks>
    public static class OpsEndpoints
    {
        /// <summary>
        /// Mapper operations-endpoints (pt. CSV-import) på den angivne route-builder.
        /// </summary>
        /// <param name="app">Den route-builder (f.eks. <see cref="WebApplication"/>) der skal have endpoints tilføjet.</param>
        /// <returns>Samme route-builder, så kald kan kædes.</returns>
        /// <remarks>
        /// Endpoints er tænkt til administrative/engangsopgaver. Anti-forfalskning (CSRF) er slået fra på upload-endpointet,
        /// fordi det ikke er en browserform med antiforgery-token, men bør kun kaldes af betroede klienter.
        /// </remarks>
        public static IEndpointRouteBuilder MapOpsEndpoints(this IEndpointRouteBuilder app)
        {
            // POST /ops/import-csv  — multipart/form-data (felt: "file")
            app.MapPost("/ops/import-csv", async (HttpRequest req, CerealAPI.Data.SqlConnectionCeral cereal) =>
            {
                // Valider content-type og hent filen
                if (!req.HasFormContentType)
                    return Results.BadRequest("Upload som multipart/form-data med feltet 'file'.");

                var form = await req.ReadFormAsync();
                var file = form.Files["file"];
                if (file is null || file.Length == 0)
                    return Results.BadRequest("Manglende fil.");
                // Parse CSV til model-liste
                using var stream = file.OpenReadStream();
                var cereals = CsvParser.ParseCereal(stream);
                if (cereals.Count == 0)
                    return Results.BadRequest("Ingen rækker fundet i CSV.");

                // Opret SqlConnection og forbered DataTable for bulk insert
                using var conn = (SqlConnection)cereal.Create();
                await conn.OpenAsync();

                var table = ToDataTable(cereals);
                // Hurtig masseindsættelse: 1:1-kolonnemapping til dbo.Cereal
                using var bulk = new SqlBulkCopy(conn)
                {
                    DestinationTableName = "dbo.Cereal"
                };

                bulk.ColumnMappings.Add("name", "name");
                bulk.ColumnMappings.Add("mfr", "mfr");
                bulk.ColumnMappings.Add("type", "type");
                bulk.ColumnMappings.Add("calories", "calories");
                bulk.ColumnMappings.Add("protein", "protein");
                bulk.ColumnMappings.Add("fat", "fat");
                bulk.ColumnMappings.Add("sodium", "sodium");
                bulk.ColumnMappings.Add("fiber", "fiber");
                bulk.ColumnMappings.Add("carbo", "carbo");
                bulk.ColumnMappings.Add("sugars", "sugars");
                bulk.ColumnMappings.Add("potass", "potass");
                bulk.ColumnMappings.Add("vitamins", "vitamins");
                bulk.ColumnMappings.Add("shelf", "shelf");
                bulk.ColumnMappings.Add("weight", "weight");
                bulk.ColumnMappings.Add("cups", "cups");
                bulk.ColumnMappings.Add("rating", "rating");

                await bulk.WriteToServerAsync(table);

                return Results.Ok(new { inserted = cereals.Count });
            })
            .DisableAntiforgery()
            .WithName("ImportCerealCsv")
            .WithSummary("Importer Cereal.csv via multipart upload")
            .WithDescription("Forventer semikolon-separeret CSV med 2. linje som datatype-linje.");

            return app;
        }
        /// <summary>
        /// Konverterer en liste af <see cref="Cereal"/> til en <see cref="DataTable"/> klar til <see cref="SqlBulkCopy"/>.
        /// </summary>
        /// <param name="cereals">De rækker der skal indsættes i databasen.</param>
        /// <returns>Et <see cref="DataTable"/> med kolonner der matcher <c>dbo.Cereal</c>.</returns>
        /// <remarks>
        /// <list type="bullet">
        /// <item>Kolonnertyper sættes eksplicit (int/double/string).</item>
        /// <item>Nullable felter mappes til <see cref="DBNull.Value"/> når de er null.</item>
        /// </list>
        /// </remarks>
        private static DataTable ToDataTable(IEnumerable<Cereal> cereals)
        {
            var dt = new DataTable();
            dt.Columns.Add("name", typeof(string));
            dt.Columns.Add("mfr", typeof(string));
            dt.Columns.Add("type", typeof(string));
            dt.Columns.Add("calories", typeof(int));
            dt.Columns.Add("protein", typeof(int));
            dt.Columns.Add("fat", typeof(int));
            dt.Columns.Add("sodium", typeof(int));
            dt.Columns.Add("fiber", typeof(double));
            dt.Columns.Add("carbo", typeof(double));
            dt.Columns.Add("sugars", typeof(int));
            dt.Columns.Add("potass", typeof(int));
            dt.Columns.Add("vitamins", typeof(int));
            dt.Columns.Add("shelf", typeof(int));
            dt.Columns.Add("weight", typeof(double));
            dt.Columns.Add("cups", typeof(double));
            dt.Columns.Add("rating", typeof(string));
            // Rækkemapping: håndter nulls -> DBNull.Value for bulkcopy-kompatibilitet
            foreach (var c in cereals)
            {
                dt.Rows.Add(
                    c.name,
                    c.mfr,
                    c.type,
                    (object?)c.calories ?? DBNull.Value,
                    (object?)c.protein ?? DBNull.Value,
                    (object?)c.fat ?? DBNull.Value,
                    (object?)c.sodium ?? DBNull.Value,
                    (object?)c.fiber ?? DBNull.Value,
                    (object?)c.carbo ?? DBNull.Value,
                    (object?)c.sugars ?? DBNull.Value,
                    (object?)c.potass ?? DBNull.Value,
                    (object?)c.vitamins ?? DBNull.Value,
                    (object?)c.shelf ?? DBNull.Value,
                    (object?)c.weight ?? DBNull.Value,
                    (object?)c.cups ?? DBNull.Value,
                    (object?)c.rating ?? DBNull.Value
                );
            }
            return dt;
        }
    }
}
