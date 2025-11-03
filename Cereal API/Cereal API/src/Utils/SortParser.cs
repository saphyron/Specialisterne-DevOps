// src/Utils/SortParser.cs
using Microsoft.AspNetCore.Http;

namespace CerealAPI.Utils
{
    /// <summary>
    /// Parser for <c>?sort=</c>-queryparametret, der konverterer en kommasepareret liste
    /// som fx <c>calories_desc,name_asc</c> til et sikkert SQL <c>ORDER BY</c>-fragment
    /// og en struktureret liste over sorteringsdele.
    /// </summary>
    /// <remarks>
    /// Parseren benytter en whitelist af tilladte kolonnenavne for at undgå SQL-injektion,
    /// ignorerer ukendte felter, og falder tilbage til <c>name ASC</c> hvis intet gyldigt er angivet.
    /// Suffikserne <c>_asc</c> og <c>_desc</c> understøttes (case-insensitivt).
    /// </remarks>
    public static class SortParser
    {
        // whitelist af kolonner der må sorteres på
        private static readonly HashSet<string> Allowed = new(StringComparer.OrdinalIgnoreCase)
        {
            "name","mfr","type","calories","protein","fat","sugars","rating","fiber","carbo","sodium","potass","vitamins","shelf","weight","cups"
        };

        /// <summary>
        /// Bygger et SQL <c>ORDER BY</c>-fragment ud fra <c>?sort=</c> i querystringen.
        /// </summary>
        /// <param name="q">HTTP-querysamling (typisk <c>HttpContext.Request.Query</c>).</param>
        /// <returns>
        /// <c>orderBy</c>: Et komplet <c>ORDER BY</c>-fragment klar til brug i SQL.<br/>
        /// <c>parts</c>: Liste over (kolonne, erDesc) for hver gyldig sorteringsdel.
        /// </returns>
        /// <remarks>
        /// Understøtter flere komma-separerede tokens, fx <c>calories_desc,name_asc</c>.
        /// Ukendte/ikke-whitelistede felter filtreres fra. Hvis intet gyldigt angives,
        /// anvendes <c>name ASC</c> som standard.
        /// </remarks>
        public static (string orderBy, List<(string col, bool desc)> parts) BuildOrderBy(IQueryCollection q)
        {
            var sort = q["sort"].ToString();
            var parts = new List<(string col, bool desc)>();

            if (!string.IsNullOrWhiteSpace(sort))
            {
                // Parse hvert token og udled retning (_desc/_asc). Ukendte felter ignoreres.
                foreach (var token in sort.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                {
                    var t = token.ToLowerInvariant();
                    var desc = t.EndsWith("_desc", StringComparison.Ordinal);
                    var col = t.Replace("_desc", "").Replace("_asc", "");
                    if (Allowed.Contains(col))
                        parts.Add((col, desc));
                }
            }
            // Fallback: sortér altid deterministisk på name, hvis intet gyldigt blev angivet
            if (parts.Count == 0)
                parts.Add(("name", false));

            var order = "ORDER BY " + string.Join(", ", parts.Select(p => $"{p.col} {(p.desc ? "DESC" : "ASC")}"));
            return (order, parts);
        }
    }
}
