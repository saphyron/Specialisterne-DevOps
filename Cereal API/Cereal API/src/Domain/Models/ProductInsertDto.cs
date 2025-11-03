// src/Domain/Models/ProductInsertDto.cs
namespace CerealAPI.Models
{
    /// <summary>
    /// Indgående DTO til POST /products for at oprette eller opdatere et produkt.
    /// (De)serialiserer request-body fra klienten.
    /// </summary>
    /// <remarks>
    /// - Når <c>id</c> er <c>null</c> oprettes et nyt produkt (insert).
    /// - Når <c>id</c> har værdi, opdateres et eksisterende produkt (update).
    /// - Felter er nullable for at muliggøre delvise opdateringer og matche kildedata.
    /// - Små bogstaver i navne giver 1:1 JSON-binding uden ekstra konfiguration.
    /// </remarks>
    public sealed class ProductInsertDto
    {
        public int? id { get; set; }
        public string name { get; set; } = "";
        public string mfr { get; set; } = "";
        public string type { get; set; } = "";
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
        public string? rating { get; set; }
    }
}
