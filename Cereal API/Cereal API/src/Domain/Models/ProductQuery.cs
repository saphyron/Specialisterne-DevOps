// src/Domain/Models/ProductQuery.cs
namespace CerealAPI.Models
{
    /// <summary>
    /// Query-DTO der binder automatisk fra querystring (via <c>[AsParameters]</c>)
    /// og bruges til filtrering/søgning på /products-endpoints.
    /// </summary>
    /// <remarks>
    /// - Null-værdier ignoreres; kun udfyldte felter bliver til filtre.
    /// - <c>nameLike</c> er til delvise match (typisk SQL LIKE).
    /// - <c>manufacturer</c> er et alias for <c>mfr</c> for mere naturlig klient-API.
    /// - Numeriske felter er nullable for at undgå 0 som implicit filter.
    /// - Kan kombineres med endpoint-specifik sortering/paging.
    /// </remarks>
    public sealed class ProductQuery
    {
        // ID og strenge
        public int? id { get; set; }
        public string? name { get; set; }
        public string? nameLike { get; set; }
        public string? mfr { get; set; }
        public string? manufacturer { get; set; }
        public string? type { get; set; }
        public string? rating { get; set; }

        // talfelter
        public int? calories { get; set; }
        public int? protein { get; set; }
        public int? fat { get; set; }
        public int? sodium { get; set; }
        public double? fiber { get; set; }
        public double? carbo { get; set; }
        public int? sugars { get; set; }
        public int? potass { get; set; }
        public int? vitamins { get; set; }
        public int? shelf { get; set; }
        public double? weight { get; set; }
        public double? cups { get; set; }
    }
}
