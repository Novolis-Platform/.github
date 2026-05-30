using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

const int DefaultAlphaThreshold = 16;

var inputPng = args.Length > 0 ? args[0] : "logo-brand-transparent.png";
var outputSvg = args.Length > 1 ? args[1] : "logo-brand-transparent.svg";
var alphaThreshold = args.Length > 2 && int.TryParse(args[2], out var parsedThreshold)
    ? parsedThreshold
    : DefaultAlphaThreshold;

var png = PngRgba.Read(inputPng);
var outlines = CleanOutliner.Trace();
var svg = SvgWriter.Write(outputSvg, inputPng, png.Width, png.Height, outlines, alphaThreshold);
File.WriteAllText(outputSvg, svg, Encoding.UTF8);

var overlaySvg = Path.Combine(
    Path.GetDirectoryName(Path.GetFullPath(outputSvg)) ?? Environment.CurrentDirectory,
    $"{Path.GetFileNameWithoutExtension(outputSvg)}-overlay.svg");
File.WriteAllText(
    overlaySvg,
    SvgWriter.WriteOverlay(overlaySvg, inputPng, png.Width, png.Height, outlines, alphaThreshold),
    Encoding.UTF8);

Console.WriteLine($"Wrote {outputSvg}");
Console.WriteLine($"Wrote {overlaySvg}");
Console.WriteLine($"Source: {inputPng}");
Console.WriteLine($"Size: {png.Width}x{png.Height}");
Console.WriteLine($"Alpha threshold: > {alphaThreshold} (raster reference only)");
Console.WriteLine($"Outline paths: {outlines.Count}");

readonly record struct PixelPoint(int X, int Y);

readonly record struct PixelEdge(PixelPoint From, PixelPoint To);

readonly record struct Vec(int X, int Y)
{
    public string ToPathPoint() => $"{X} {Y}";
}

readonly record struct SvgOutline(string Id, string Kind, string DataLabel, string Fill, VectorPath Path)
{
    public string PathData => Path.ToPathData();
}

sealed class VectorPath
{
    private readonly List<string> _commands = [];
    private readonly List<Vec> _points = [];
    private Vec _current;

    private VectorPath(Vec start)
    {
        _commands.Add($"M{start.ToPathPoint()}");
        _points.Add(start);
        _current = start;
    }

    public static VectorPath Start(Vec point) => new(point);

    public VectorPath LineTo(Vec point)
    {
        _commands.Add($"L{point.ToPathPoint()}");
        _points.Add(point);
        _current = point;
        return this;
    }

    public VectorPath HorizontalTo(int x)
    {
        _commands.Add($"H{x}");
        _current = _current with { X = x };
        _points.Add(_current);
        return this;
    }

    public VectorPath VerticalTo(int y)
    {
        _commands.Add($"V{y}");
        _current = _current with { Y = y };
        _points.Add(_current);
        return this;
    }

    public VectorPath ArcTo(int radiusX, int radiusY, bool largeArc, bool sweep, Vec point)
    {
        _commands.Add($"A{radiusX} {radiusY} 0 {(largeArc ? 1 : 0)} {(sweep ? 1 : 0)} {point.ToPathPoint()}");
        _points.Add(point);
        _current = point;
        return this;
    }

    public VectorPath Close()
    {
        _commands.Add("Z");
        return this;
    }

    public string ToPathData() => string.Join(' ', _commands);

    public IReadOnlyList<Vec> Points => _points;
}

static class CleanOutliner
{
    private const int CanonicalSwirlInnerRadius = 255;
    private const int CanonicalSwirlOuterRadius = 265;

    public static List<SvgOutline> Trace()
    {
        var upperLeftInner = P(413, 313);
        var upperLeftCorner = P(456, 313);
        var upperRightTip = P(850, 332);

        var leftTopOuter = P(399, 326);
        var leftTopInner = P(433, 362);
        var leftBottomOuter = P(526, 732);

        var rightTopOuter = P(871, 368);
        var rightBottomOuter = P(827, 671);
        var rightBottomInner = P(820, 621);

        var lowerLeftOuter = P(526, 732);
        var lowerRightOuter = P(810, 688);
        var lowerRightInner = P(768, 688);
        var lowerLeftInner = P(520, 711);

        var diagonalTopLeft = P(398, 326);
        var diagonalTopRight = P(531, 326);
        var diagonalShoulder = P(824, 619);
        var diagonalRightFlat = P(854, 619);
        var diagonalRightDrop = P(854, 640);
        var diagonalBottomRight = P(837, 671);
        var diagonalBottomLeft = P(731, 671);
        var diagonalLeftReturn = P(398, 326);

        var leftStemTop = P(472, 433);
        var leftStemShoulder = P(540, 496);
        var leftStemLowerRight = P(540, 616);
        var leftStemFoot = P(504, 655);
        var leftStemLowerLeft = P(472, 655);

        var rightStemTopLeft = P(734, 367);
        var rightStemCap = P(771, 328);
        var rightStemTopRight = P(804, 328);
        var rightStemBottomRight = P(804, 581);
        var rightStemBottomLeft = P(734, 513);

        var starTop = P(874, 241);
        var starUpperInner = P(884, 273);
        var starRight = P(918, 285);
        var starLowerInner = P(884, 298);
        var starBottom = P(874, 329);
        var starLowerLeftInner = P(866, 300);
        var starLeft = P(831, 285);
        var starUpperLeftInner = P(865, 273);

        return
        [
            new("shape-swirl-upper", "arc-sector", "swirl_upper", "url(#mark-cyan)",
                // Locked: confirmed perfect. Do not split or add intermediate arc points.
                Path(upperLeftInner)
                    .HorizontalTo(upperLeftCorner.X)
                    .ArcTo(CanonicalSwirlInnerRadius, CanonicalSwirlInnerRadius, largeArc: false, sweep: true, upperRightTip)
                    .ArcTo(CanonicalSwirlOuterRadius, CanonicalSwirlOuterRadius, largeArc: false, sweep: false, upperLeftInner)
                    .Close()),

            new("shape-swirl-left", "arc-sector", "swirl_left", "url(#mark-left)",
                Path(leftTopOuter)
                    .ArcTo(CanonicalSwirlInnerRadius, CanonicalSwirlInnerRadius, largeArc: false, sweep: false, leftBottomOuter)
                    .ArcTo(CanonicalSwirlOuterRadius, CanonicalSwirlOuterRadius, largeArc: false, sweep: true, leftTopInner)
                    .Close()),

            new("shape-swirl-right", "arc-sector", "swirl_right", "url(#mark-right)",
                Path(rightTopOuter)
                    .ArcTo(CanonicalSwirlInnerRadius, CanonicalSwirlInnerRadius, largeArc: false, sweep: true, rightBottomOuter)
                    .LineTo(rightBottomInner)
                    .ArcTo(CanonicalSwirlOuterRadius, CanonicalSwirlOuterRadius, largeArc: false, sweep: false, rightTopOuter)
                    .Close()),

            new("shape-swirl-lower", "arc-sector", "swirl_lower", "url(#mark-lower)",
                Path(lowerLeftInner)
                    .LineTo(lowerLeftOuter)
                    .ArcTo(CanonicalSwirlInnerRadius, CanonicalSwirlInnerRadius, largeArc: false, sweep: false, lowerRightOuter)
                    .LineTo(lowerRightInner)
                    .ArcTo(CanonicalSwirlOuterRadius, CanonicalSwirlOuterRadius, largeArc: false, sweep: true, lowerLeftInner)
                    .Close()),

            new("shape-diagonal", "straight", "n_diagonal", "url(#mark-diagonal)",
                Path(diagonalTopLeft)
                    .HorizontalTo(diagonalTopRight.X)
                    .LineTo(diagonalShoulder)
                    .HorizontalTo(diagonalRightFlat.X)
                    .VerticalTo(diagonalRightDrop.Y)
                    .LineTo(diagonalBottomRight)
                    .HorizontalTo(diagonalBottomLeft.X)
                    .LineTo(diagonalLeftReturn)
                    .Close()),

            new("shape-left-stem", "straight", "n_left_stem", "url(#mark-left-stem)",
                Path(leftStemTop)
                    .LineTo(leftStemShoulder)
                    .VerticalTo(leftStemLowerRight.Y)
                    .LineTo(leftStemFoot)
                    .HorizontalTo(leftStemLowerLeft.X)
                    .Close()),

            new("shape-right-stem", "straight", "n_right_stem", "url(#mark-right-stem)",
                Path(rightStemTopLeft)
                    .LineTo(rightStemCap)
                    .HorizontalTo(rightStemTopRight.X)
                    .VerticalTo(rightStemBottomRight.Y)
                    .LineTo(rightStemBottomLeft)
                    .Close()),

            new("shape-star", "straight", "star", "url(#star-gradient)",
                Path(starTop)
                    .LineTo(starUpperInner)
                    .LineTo(starRight)
                    .LineTo(starLowerInner)
                    .LineTo(starBottom)
                    .LineTo(starLowerLeftInner)
                    .LineTo(starLeft)
                    .LineTo(starUpperLeftInner)
                    .Close()),
        ];
    }

    private static Vec P(int x, int y) => new(x, y);

    private static VectorPath Path(Vec start) => VectorPath.Start(start);
}

static class PixelOutliner
{
    public static List<List<PixelPoint>> Trace(bool[,] mask)
    {
        var height = mask.GetLength(0);
        var width = mask.GetLength(1);
        var edges = new HashSet<PixelEdge>();

        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                if (!mask[y, x])
                {
                    continue;
                }

                if (y == 0 || !mask[y - 1, x])
                {
                    edges.Add(new PixelEdge(new PixelPoint(x, y), new PixelPoint(x + 1, y)));
                }

                if (x == width - 1 || !mask[y, x + 1])
                {
                    edges.Add(new PixelEdge(new PixelPoint(x + 1, y), new PixelPoint(x + 1, y + 1)));
                }

                if (y == height - 1 || !mask[y + 1, x])
                {
                    edges.Add(new PixelEdge(new PixelPoint(x + 1, y + 1), new PixelPoint(x, y + 1)));
                }

                if (x == 0 || !mask[y, x - 1])
                {
                    edges.Add(new PixelEdge(new PixelPoint(x, y + 1), new PixelPoint(x, y)));
                }
            }
        }

        var byStart = edges
            .GroupBy(edge => edge.From)
            .ToDictionary(
                group => group.Key,
                group => group.Select(edge => edge.To).OrderBy(point => point.Y).ThenBy(point => point.X).ToList());

        var remaining = new HashSet<PixelEdge>(edges);
        var outlines = new List<List<PixelPoint>>();

        while (remaining.Count > 0)
        {
            var first = remaining.OrderBy(edge => edge.From.Y).ThenBy(edge => edge.From.X).ThenBy(edge => edge.To.Y).ThenBy(edge => edge.To.X).First();
            var path = new List<PixelPoint> { first.From };
            var current = first;
            var previousDirection = Direction(first);

            while (true)
            {
                remaining.Remove(current);
                RemoveFromStartMap(byStart, current);
                path.Add(current.To);

                if (current.To == first.From)
                {
                    break;
                }

                if (!byStart.TryGetValue(current.To, out var candidates) || candidates.Count == 0)
                {
                    break;
                }

                var nextPoint = ChooseNext(current.To, candidates, previousDirection);
                var next = new PixelEdge(current.To, nextPoint);
                if (!remaining.Contains(next))
                {
                    break;
                }

                previousDirection = Direction(next);
                current = next;
            }

            var simplified = SimplifyCollinear(path);
            if (simplified.Count >= 4)
            {
                outlines.Add(simplified);
            }
        }

        return outlines
            .OrderByDescending(PolygonAreaAbs)
            .ToList();
    }

    private static void RemoveFromStartMap(Dictionary<PixelPoint, List<PixelPoint>> byStart, PixelEdge edge)
    {
        if (!byStart.TryGetValue(edge.From, out var list))
        {
            return;
        }

        list.Remove(edge.To);
        if (list.Count == 0)
        {
            byStart.Remove(edge.From);
        }
    }

    private static PixelPoint ChooseNext(PixelPoint start, List<PixelPoint> candidates, PixelPoint previousDirection)
    {
        var straight = candidates.FirstOrDefault(candidate => Direction(start, candidate) == previousDirection);
        if (straight != default)
        {
            return straight;
        }

        return candidates[0];
    }

    private static PixelPoint Direction(PixelEdge edge) => Direction(edge.From, edge.To);

    private static PixelPoint Direction(PixelPoint from, PixelPoint to)
    {
        return new PixelPoint(Math.Sign(to.X - from.X), Math.Sign(to.Y - from.Y));
    }

    private static List<PixelPoint> SimplifyCollinear(List<PixelPoint> points)
    {
        if (points.Count <= 3)
        {
            return points;
        }

        if (points[0] == points[^1])
        {
            points = points[..^1];
        }

        var simplified = new List<PixelPoint>();
        for (var i = 0; i < points.Count; i++)
        {
            var previous = points[(i - 1 + points.Count) % points.Count];
            var current = points[i];
            var next = points[(i + 1) % points.Count];

            if ((previous.X == current.X && current.X == next.X) ||
                (previous.Y == current.Y && current.Y == next.Y))
            {
                continue;
            }

            simplified.Add(current);
        }

        return simplified;
    }

    private static double PolygonAreaAbs(List<PixelPoint> points)
    {
        long area2 = 0;
        for (var i = 0; i < points.Count; i++)
        {
            var a = points[i];
            var b = points[(i + 1) % points.Count];
            area2 += (long)a.X * b.Y - (long)b.X * a.Y;
        }

        return Math.Abs(area2) / 2.0;
    }
}

static class SvgWriter
{
    public static string Write(
        string outputSvg,
        string inputPng,
        int width,
        int height,
        IReadOnlyList<SvgOutline> outlines,
        int alphaThreshold)
    {
        _ = outputSvg;
        _ = inputPng;

        var sb = new StringBuilder();
        sb.AppendLine($"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-label="Novolis">""");
        sb.AppendLine("  <title>Novolis vector logo</title>");
        sb.AppendLine("  <defs>");
        sb.AppendLine("""    <linearGradient id="mark-cyan" x1="412" y1="206" x2="850" y2="332" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#2fdfff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#0997ff"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="mark-left" x1="314" y1="326" x2="430" y2="639" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#12c7ff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#237cff"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="mark-right" x1="871" y1="368" x2="824" y2="674" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#2f8cff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#8f37ff"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="mark-lower" x1="526" y1="714" x2="812" y2="687" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#7a42ff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#b246ff"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="mark-diagonal" x1="405" y1="327" x2="854" y2="671" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#16cfff"/>""");
        sb.AppendLine("""      <stop offset="0.52" stop-color="#4d86ff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#9c42ff"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="mark-left-stem" x1="472" y1="433" x2="540" y2="656" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#0ba8ff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#0677d9"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="mark-right-stem" x1="734" y1="325" x2="804" y2="581" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#2aa5ff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#6138d9"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="star-gradient" x1="831" y1="241" x2="918" y2="329" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#35d8ff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#9b60ff"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <linearGradient id="tagline-gradient" x1="203" y1="967" x2="1051" y2="999" gradientUnits="userSpaceOnUse">""");
        sb.AppendLine("""      <stop offset="0" stop-color="#08bfff"/>""");
        sb.AppendLine("""      <stop offset="0.52" stop-color="#7547ff"/>""");
        sb.AppendLine("""      <stop offset="1" stop-color="#1a8dff"/>""");
        sb.AppendLine("    </linearGradient>");
        sb.AppendLine("""    <filter id="wordmark-glow" x="-5%" y="-20%" width="110%" height="150%">""");
        sb.AppendLine("""      <feDropShadow dx="0" dy="2" stdDeviation="1.2" flood-color="#2f8cff" flood-opacity="0.45"/>""");
        sb.AppendLine("    </filter>");
        sb.AppendLine("  </defs>");
        sb.AppendLine($"""  <g id="vector-mark" data-alpha-threshold="{alphaThreshold}">""");

        foreach (var outline in outlines)
        {
            sb.AppendLine($"""    <path id="{outline.Id}" data-kind="{outline.Kind}" data-label="{outline.DataLabel}" fill="{outline.Fill}" d="{outline.PathData}"/>""");
        }

        sb.AppendLine("  </g>");
        sb.AppendLine("""  <g id="vector-wordmark" font-family="Consolas, 'Cascadia Mono', 'Courier New', monospace" text-anchor="start">""");
        sb.AppendLine("""    <text x="161" y="912" font-size="133" font-weight="700" fill="#f7fbff" textLength="936" lengthAdjust="spacingAndGlyphs" filter="url(#wordmark-glow)">NOVOLIS</text>""");
        sb.AppendLine("""    <text x="203" y="999" font-size="35" font-weight="700" fill="url(#tagline-gradient)" textLength="848" lengthAdjust="spacingAndGlyphs">BUILD • CREATE • EXPLORE</text>""");
        sb.AppendLine("  </g>");
        sb.AppendLine("</svg>");
        return sb.ToString();
    }

    public static string WriteOverlay(
        string outputSvg,
        string inputPng,
        int width,
        int height,
        IReadOnlyList<SvgOutline> outlines,
        int alphaThreshold)
    {
        var href = Path.GetRelativePath(
                Path.GetDirectoryName(Path.GetFullPath(outputSvg)) ?? Environment.CurrentDirectory,
                Path.GetFullPath(inputPng))
            .Replace('\\', '/');

        var sb = new StringBuilder();
        sb.AppendLine($"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-label="Novolis logo construction overlay">""");
        sb.AppendLine("  <title>Novolis logo construction overlay</title>");
        sb.AppendLine("  <style>");
        sb.AppendLine("    .shape-outline { fill: none; stroke: #ff2bd6; stroke-width: 2.5; stroke-linejoin: round; stroke-linecap: round; vector-effect: non-scaling-stroke; }");
        sb.AppendLine("    .point { fill: #ffe66d; stroke: #101522; stroke-width: 2; vector-effect: non-scaling-stroke; }");
        sb.AppendLine("    .point-label { fill: #fff9d6; font: 18px Consolas, 'Cascadia Mono', monospace; paint-order: stroke; stroke: #101522; stroke-width: 4; stroke-linejoin: round; }");
        sb.AppendLine("    .shape-label { fill: #ffffff; font: 22px Consolas, 'Cascadia Mono', monospace; paint-order: stroke; stroke: #101522; stroke-width: 5; stroke-linejoin: round; }");
        sb.AppendLine("  </style>");
        sb.AppendLine($"""  <image id="raster-reference" width="{width}" height="{height}" href="{EscapeXml(href)}" opacity="0.42"/>""");
        sb.AppendLine($"""  <g id="vector-shapes" data-alpha-threshold="{alphaThreshold}" opacity="0.55">""");

        foreach (var outline in OverlayOutlines(outlines))
        {
            sb.AppendLine($"""    <path id="{outline.Id}-fill" data-label="{outline.DataLabel}" fill="{outline.Fill}" d="{outline.PathData}"/>""");
        }

        sb.AppendLine("  </g>");
        sb.AppendLine("""  <g id="shape-outlines">""");

        foreach (var outline in OverlayOutlines(outlines))
        {
            sb.AppendLine($"""    <path id="{outline.Id}-outline" class="shape-outline" data-label="{outline.DataLabel}" d="{outline.PathData}"/>""");
        }

        sb.AppendLine("  </g>");
        sb.AppendLine("""  <g id="control-points">""");

        foreach (var outline in OverlayOutlines(outlines))
        {
            var points = outline.Path.Points;
            for (var i = 0; i < points.Count; i++)
            {
                var point = points[i];
                var label = PointLabel(outline.DataLabel, i);
                sb.AppendLine($"""    <circle id="{outline.Id}-p{i + 1}" class="point" data-label="{EscapeXml(label)}" cx="{point.X}" cy="{point.Y}" r="6"/>""");
                sb.AppendLine($"""    <text class="point-label" x="{point.X + 9}" y="{point.Y - 9}">{EscapeXml(label)}</text>""");
            }

            if (points.Count > 0)
            {
                var anchor = points[0];
                sb.AppendLine($"""    <text class="shape-label" x="{anchor.X + 18}" y="{anchor.Y + 25}">{EscapeXml(outline.DataLabel)}</text>""");
            }
        }

        sb.AppendLine("  </g>");
        sb.AppendLine("</svg>");
        return sb.ToString();
    }

    private static IEnumerable<SvgOutline> OverlayOutlines(IEnumerable<SvgOutline> outlines)
    {
        return outlines.Where(outline =>
            outline.DataLabel is not "swirl_upper" and not "n_left_stem" and not "n_right_stem");
    }

    private static string PointLabel(string shapeLabel, int pointIndex)
    {
        return shapeLabel switch
        {
            "swirl_upper" => pointIndex switch
            {
                0 => "swirl_upper:start",
                1 => "swirl_upper:corner",
                2 => "swirl_upper:tip",
                3 => "swirl_upper:close",
                _ => $"{shapeLabel}:{pointIndex + 1}"
            },
            _ => $"{shapeLabel}:{pointIndex + 1}"
        };
    }

    private static string PathData(IReadOnlyList<PixelPoint> points)
    {
        var sb = new StringBuilder();
        sb.Append('M').Append(points[0].X).Append(' ').Append(points[0].Y);

        for (var i = 1; i < points.Count; i++)
        {
            var previous = points[i - 1];
            var current = points[i];
            if (current.Y == previous.Y)
            {
                sb.Append('H').Append(current.X);
            }
            else if (current.X == previous.X)
            {
                sb.Append('V').Append(current.Y);
            }
            else
            {
                sb.Append('L').Append(current.X).Append(' ').Append(current.Y);
            }
        }

        sb.Append('Z');
        return sb.ToString();
    }

    private static string EscapeXml(string value)
    {
        return value
            .Replace("&", "&amp;", StringComparison.Ordinal)
            .Replace("\"", "&quot;", StringComparison.Ordinal)
            .Replace("<", "&lt;", StringComparison.Ordinal)
            .Replace(">", "&gt;", StringComparison.Ordinal);
    }
}

sealed class PngRgba
{
    private static readonly byte[] PngSignature = [137, 80, 78, 71, 13, 10, 26, 10];

    public required int Width { get; init; }

    public required int Height { get; init; }

    public required byte[] Alpha { get; init; }

    public static PngRgba Read(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> signature = stackalloc byte[8];
        stream.ReadExactly(signature);
        if (!signature.SequenceEqual(PngSignature))
        {
            throw new InvalidDataException("Input is not a PNG file.");
        }

        var idat = new MemoryStream();
        int? width = null;
        int? height = null;
        byte bitDepth = 0;
        byte colorType = 0;

        while (stream.Position < stream.Length)
        {
            var length = ReadUInt32(stream);
            var typeBytes = new byte[4];
            stream.ReadExactly(typeBytes);
            var type = Encoding.ASCII.GetString(typeBytes);
            var data = new byte[length];
            stream.ReadExactly(data);
            _ = ReadUInt32(stream); // CRC

            switch (type)
            {
                case "IHDR":
                    width = BinaryPrimitives.ReadInt32BigEndian(data.AsSpan(0, 4));
                    height = BinaryPrimitives.ReadInt32BigEndian(data.AsSpan(4, 4));
                    bitDepth = data[8];
                    colorType = data[9];
                    break;
                case "IDAT":
                    idat.Write(data);
                    break;
                case "IEND":
                    return Decode(width, height, bitDepth, colorType, idat.ToArray());
            }
        }

        throw new InvalidDataException("PNG ended before IEND.");
    }

    private static PngRgba Decode(int? width, int? height, byte bitDepth, byte colorType, byte[] compressed)
    {
        if (width is null || height is null)
        {
            throw new InvalidDataException("PNG is missing IHDR.");
        }

        if (bitDepth != 8)
        {
            throw new NotSupportedException($"Only 8-bit PNGs are supported; got bit depth {bitDepth}.");
        }

        var bytesPerPixel = colorType switch
        {
            6 => 4, // RGBA
            4 => 2, // grayscale + alpha
            2 => 3, // RGB, no alpha
            0 => 1, // grayscale, no alpha
            _ => throw new NotSupportedException($"PNG color type {colorType} is not supported by this outline script.")
        };

        using var compressedStream = new MemoryStream(compressed);
        using var zlib = new ZLibStream(compressedStream, CompressionMode.Decompress);
        using var raw = new MemoryStream();
        zlib.CopyTo(raw);

        var decompressed = raw.ToArray();
        var stride = width.Value * bytesPerPixel;
        var expected = (stride + 1) * height.Value;
        if (decompressed.Length < expected)
        {
            throw new InvalidDataException($"PNG data is shorter than expected ({decompressed.Length} < {expected}).");
        }

        var pixels = new byte[stride * height.Value];
        var previous = new byte[stride];
        var sourceOffset = 0;
        var targetOffset = 0;

        for (var y = 0; y < height.Value; y++)
        {
            var filter = decompressed[sourceOffset++];
            var row = decompressed.AsSpan(sourceOffset, stride).ToArray();
            sourceOffset += stride;
            Unfilter(row, previous, bytesPerPixel, filter);
            row.CopyTo(pixels, targetOffset);
            row.CopyTo(previous, 0);
            targetOffset += stride;
        }

        var alpha = new byte[width.Value * height.Value];
        for (var y = 0; y < height.Value; y++)
        {
            for (var x = 0; x < width.Value; x++)
            {
                var pixelOffset = y * stride + x * bytesPerPixel;
                alpha[y * width.Value + x] = colorType switch
                {
                    6 => pixels[pixelOffset + 3],
                    4 => pixels[pixelOffset + 1],
                    _ => byte.MaxValue
                };
            }
        }

        return new PngRgba
        {
            Width = width.Value,
            Height = height.Value,
            Alpha = alpha
        };
    }

    private static void Unfilter(byte[] row, byte[] previous, int bytesPerPixel, byte filter)
    {
        for (var i = 0; i < row.Length; i++)
        {
            var left = i >= bytesPerPixel ? row[i - bytesPerPixel] : 0;
            var up = previous[i];
            var upLeft = i >= bytesPerPixel ? previous[i - bytesPerPixel] : 0;

            row[i] = filter switch
            {
                0 => row[i],
                1 => unchecked((byte)(row[i] + left)),
                2 => unchecked((byte)(row[i] + up)),
                3 => unchecked((byte)(row[i] + ((left + up) / 2))),
                4 => unchecked((byte)(row[i] + Paeth(left, up, upLeft))),
                _ => throw new InvalidDataException($"Unknown PNG filter {filter}.")
            };
        }
    }

    private static byte Paeth(int left, int up, int upLeft)
    {
        var p = left + up - upLeft;
        var pa = Math.Abs(p - left);
        var pb = Math.Abs(p - up);
        var pc = Math.Abs(p - upLeft);

        if (pa <= pb && pa <= pc)
        {
            return (byte)left;
        }

        return pb <= pc ? (byte)up : (byte)upLeft;
    }

    private static uint ReadUInt32(Stream stream)
    {
        Span<byte> buffer = stackalloc byte[4];
        stream.ReadExactly(buffer);
        return BinaryPrimitives.ReadUInt32BigEndian(buffer);
    }
}
