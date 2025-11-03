// src/Utils/CsvParser.cs
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using CerealAPI.Models;

namespace CerealAPI.Utils
{
    /// <summary>
    /// Simpel CSV-parser til Cereal-data: læser semikolon-separerede filer og mapper til <see cref="Cereal"/>.
    /// Spring­er 2. linje (datatype-linje) over og tolker "-1" som <c>null</c> for talfelter.
    /// </summary>
    /// <remarks>
    /// Forventer kolonneorden: name;mfr;type;calories;protein;fat;sodium;fiber;carbo;sugars;potass;vitamins;shelf;weight;cups;rating.
    /// Parseren er bevidst "lightweight": der håndteres ikke anførselstegn/escaped separatorer (ingen RFC 4180).
    /// Tal tolkes først med <see cref="CultureInfo.InvariantCulture"/> og falder derefter tilbage til "da-DK".
    /// </remarks>
    public static class CsvParser
    {
        /// <summary>
        /// Læser en semikolon-CSV fra en stream og returnerer en liste af <see cref="Cereal"/>.
        /// </summary>
        /// <param name="csvStream">Inddata-stream med CSV-indhold (første linje er header, anden linje er datatyper).</param>
        /// <returns>En liste af <see cref="Cereal"/>; tom hvis input er tomt eller header mangler.</returns>
        /// <remarks>
        /// Linje 1 antages at være kolonneheader; linje 2 (datatype-linje) ignoreres.
        /// Tomme linjer springes over. Feltværdien "-1" konverteres til <c>null</c> for talfelter.
        /// </remarks>
        public static List<Cereal> ParseCereal(Stream csvStream)
        {
            var list = new List<Cereal>();
            using var reader = new StreamReader(csvStream);

            string? header = reader.ReadLine();     // læs header
            if (header == null) return list;

            _ = reader.ReadLine();                  // skip datatype-linje (2. linje)

            string? line;
            while ((line = reader.ReadLine()) != null)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                // Simple split på ';' (ingen understøttelse af quoted felter)
                var p = line.Split(';');
                string Get(int i) => i < p.Length ? p[i].Trim() : "";

                var cereal = new Cereal
                {
                    name = Get(0),
                    mfr = Get(1),
                    type = Get(2),
                    calories = ToNullableInt(Get(3)),
                    protein = ToNullableInt(Get(4)),
                    fat = ToNullableInt(Get(5)),
                    sodium = ToNullableInt(Get(6)),
                    fiber = ToNullableDouble(Get(7)),
                    carbo = ToNullableDouble(Get(8)),
                    sugars = ToNullableInt(Get(9)),
                    potass = ToNullableInt(Get(10)),
                    vitamins = ToNullableInt(Get(11)),
                    shelf = ToNullableInt(Get(12)),
                    weight = ToNullableDouble(Get(13)),
                    cups = ToNullableDouble(Get(14)),
                    rating = ToNullableString(Get(15))
                };

                list.Add(cereal);
            }

            return list;
        }
        /// <summary>
        /// Konverterer en streng til <c>int?</c>; <c>null</c> ved tom, whitespace eller "-1".
        /// </summary>
        /// <param name="s">Kildestreng.</param>
        /// <returns>Heltal eller <c>null</c>.</returns>
        /// <remarks>Bruger <see cref="CultureInfo.InvariantCulture"/> til parsing.</remarks>
        static int? ToNullableInt(string s)
        {
            if (string.IsNullOrWhiteSpace(s) || s == "-1") return null;
            return int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : (int?)null;
        }
        /// <summary>
        /// Konverterer en streng til <c>double?</c>; <c>null</c> ved tom, whitespace eller "-1".
        /// </summary>
        /// <param name="s">Kildestreng.</param>
        /// <returns>Komma-/punktumtal eller <c>null</c>.</returns>
        /// <remarks>
        /// Forsøger først parsing med invariant kultur; dernæst med "da-DK" for at acceptere komma som decimalseparator.
        /// </remarks>
        static double? ToNullableDouble(string s)
        {
            if (string.IsNullOrWhiteSpace(s) || s == "-1") return null;

            if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var inv))
                return inv;

            if (double.TryParse(s, NumberStyles.Float, new CultureInfo("da-DK"), out var dk))
                return dk;

            return null;
        }
        /// <summary>
        /// Trimmer en streng; returnerer <c>null</c> ved tom, whitespace eller "-1".
        /// </summary>
        /// <param name="s">Kildestreng.</param>
        static string? ToNullableString(string s)
        {
            if (string.IsNullOrWhiteSpace(s) || s == "-1") return null;
            return s.Trim();
        }
    }
}
