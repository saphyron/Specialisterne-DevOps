// src/Utils/FilterParser.cs
using System.Web;
using System.Text.RegularExpressions;
using Dapper;

namespace CerealAPI.Utils;

/// <summary>
/// Parser querystring-filtre til en sikker SQL WHERE-klausul + Dapper-parameterbindinger.
/// Formålet er at understøtte både “rå” udtryk (fx <c>calories&gt;=100</c>) og alias‐nøgler
/// (fx <c>calories_gte=100</c>) uden at åbne for SQL injection.
/// </summary>
/// <remarks>
/// Implementerer en whitelist af tilladte felter (kolonnenavne) og en whitelist af operatorer.
/// Værdier bindes altid som parametre via <see cref="DynamicParameters"/> for at undgå injection.
/// Støtter to syntakser samtidig:
/// 1) Rå udtryk i selve querystringen (URL-decoded) via regex (fx <c>?calories%3E=100&amp;protein&lt;=10</c>).
/// 2) Alias-suffikser pr. nøgle, fx <c>_gte</c>, <c>_lte</c>, <c>_gt</c>, <c>_lt</c>, <c>_eq</c>, <c>_neq</c>.
/// </remarks>
public static class FilterParser
{
    // whitelist: query-felt -> DB-kolonne
    private static readonly Dictionary<string, string> Allowed = new(StringComparer.OrdinalIgnoreCase)
    {
        ["name"] = "name",
        ["mfr"] = "mfr",
        ["type"] = "type",
        ["calories"] = "calories",
        ["protein"] = "protein",
        ["fat"] = "fat",
        ["sodium"] = "sodium",
        ["fiber"] = "fiber",
        ["carbo"] = "carbo",
        ["sugars"] = "sugars",
        ["potass"] = "potass",
        ["vitamins"] = "vitamins",
        ["shelf"] = "shelf",
        ["weight"] = "weight",
        ["cups"] = "cups",
        ["rating"] = "rating"
    };

    // Tilladte operatorer (whitelist)
    private static readonly Dictionary<string, string> OpMap = new()
    {
        ["="] = "=",
        ["!="] = "!=",
        [">"] = ">",
        [">="] = ">=",
        ["<"] = "<",
        ["<="] = "<="
    };

    // Regex der fanger fx calories>=100  eller  name=All-Bran
    private static readonly Regex RawExpr = new(@"(?<f>[a-zA-Z_]\w*)\s*(?<op>!=|>=|<=|=|>|<)\s*(?<v>[^&]+)",
        RegexOptions.Compiled);
        
    /// <summary>
    /// Bygger en SQL WHERE-klausul og parameterbindinger ud fra querystringen.
    /// Understøtter både rå udtryk i hele queryen og alias‐nøgler pr. parameter.
    /// </summary>
    /// <param name="rawQuery">Den rå querystring (inkl. <c>?</c>), typisk <c>ctx.Request.QueryString.Value</c>.</param>
    /// <param name="q">Den parsede samling af nøgler/værdier (typisk <c>ctx.Request.Query</c>).</param>
    /// <returns>
    /// En tuple hvor:
    /// <c>whereSql</c> er en evt. tom streng eller <c>"WHERE ..."</c>,
    /// og <c>bind</c> er <see cref="DynamicParameters"/> klar til Dapper (alle værdier er parametre).
    /// </returns>
    /// <remarks>
    /// 1) Rå-mode: hele <paramref name="rawQuery"/> URL-decodes og matches mod <see cref="RawExpr"/>.
    /// Kun felter/operatører på whitelist medtages, og værdier bindes som <c>@p0</c>, <c>@p1</c>, …<br/>
    /// 2) Alias-mode: gennemløber <paramref name="q"/> for suffikserne
    /// <c>_gte</c>, <c>_lte</c>, <c>_gt</c>, <c>_lt</c>, <c>_eq</c>, <c>_neq</c> og mapper til de tilsvarende operatorer.
    /// Værdier forsøges konverteret til <c>int</c> eller <c>double</c> (InvariantCulture); ellers behandles de som string.
    /// </remarks>
    public static (string whereSql, DynamicParameters bind) BuildWhere(string? rawQuery, IQueryCollection q)
    {
        var dp = new DynamicParameters();
        var whereParts = new List<string>();
        int i = 0;

        // 1) Raw‐mode: parse hele querystringen (URL-decoded)
        if (!string.IsNullOrEmpty(rawQuery))
        {
            var decoded = HttpUtility.UrlDecode(rawQuery.TrimStart('?'));
            foreach (Match m in RawExpr.Matches(decoded))
            {
                var f = m.Groups["f"].Value;
                var op = m.Groups["op"].Value;
                var v = m.Groups["v"].Value;

                if (!Allowed.TryGetValue(f, out var col)) continue;
                if (!OpMap.TryGetValue(op, out var sqlOp)) continue;

                var p = $"@p{i++}";
                whereParts.Add($"{col} {sqlOp} {p}");
                dp.Add(p, TryConvert(v));
            }
        }

        // 2) Alias‐mode: calories_gte=100, calories_lte=200, name_eq=All-Bran, rating_neq=50
        var aliasOps = new (string suffix, string op)[] {
            ("_gte", ">="), ("_lte", "<="), ("_gt", ">"), ("_lt", "<"), ("_eq", "="), ("_neq", "!=")
        };

        foreach (var kv in q)
        {
            var key = kv.Key;
            var val = kv.Value.ToString();
            foreach (var (sfx, op) in aliasOps)
            {
                if (key.EndsWith(sfx, StringComparison.OrdinalIgnoreCase))
                {
                    var field = key[..^sfx.Length];
                    if (!Allowed.TryGetValue(field, out var col)) break;

                    var p = $"@p{i++}";
                    whereParts.Add($"{col} {op} {p}");
                    dp.Add(p, TryConvert(val));
                    break;
                }
            }
        }

        var whereSql = whereParts.Count > 0 ? "WHERE " + string.Join(" AND ", whereParts) : "";
        return (whereSql, dp);
    }
    /// <summary>
    /// Forsøger at konvertere en tekst til <c>int</c> eller <c>double</c> (InvariantCulture); ellers returneres original streng.
    /// </summary>
    /// <param name="s">Kildestreng fra querystring.</param>
    /// <returns>Et <c>int</c>, <c>double</c> eller original tekst.</returns>
    /// <remarks>
    /// Bevidst simpel konvertering; formålet er at få korrekte typer ind i Dapper-parameterbindingen,
    /// ikke at validere domænelogik.
    /// </remarks>
    private static object TryConvert(string s)
    {
        // Prøv int/double, ellers brug string
        if (int.TryParse(s, out var i)) return i;
        if (double.TryParse(s, System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var d)) return d;
        return s;
    }
}
