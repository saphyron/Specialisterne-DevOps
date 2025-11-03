// src/Domain/Models/Cereal.cs
namespace CerealAPI.Models
{
    /// <summary>
    /// Domænemodel for en morgenmads-cereal (en enkelt række i datasættet/tabellen).
    /// Bruges til at (de)serialisere JSON og til data-adgangslagets mapping.
    /// </summary>
    /// <remarks>
    /// Feltnavne er bevidst med små bogstaver for at matche kildedata/SQL-kolonner
    /// og give 1:1 JSON-nøgler uden ekstra konfiguration. De fleste numeriske felter er
    /// nullable for at kunne repræsentere manglende/ukendte værdier fra datasættet.
    /// </remarks>
    public sealed class Cereal
    {
        public int id { get; set; }  // Auto-increment PK
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
