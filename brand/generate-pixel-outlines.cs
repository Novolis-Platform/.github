using System.Diagnostics;
using System.Text;

// =============================================================================
// App — CLI entry point (thin; delegates to library sections below)
// =============================================================================

return BrandLogoApp.Run(args);

// =============================================================================
// Library: SVG core — geometry, paths, document builder, XML helpers
// =============================================================================

readonly record struct Vec(int X, int Y)
{
    public string ToPathPoint() => $"{X} {Y}";
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

readonly record struct SvgShape(string Id, string Kind, string Label, string Fill, VectorPath Path)
{
    public string PathData => Path.ToPathData();
}

sealed class SvgDocument
{
    private readonly StringBuilder _sb = new();
    private readonly int _width;
    private readonly int _height;
    private readonly string _viewBox;
    private readonly string _ariaLabel;
    private readonly string _title;

    public SvgDocument(int width, int height, string ariaLabel, string title, string? viewBox = null)
    {
        _width = width;
        _height = height;
        _viewBox = viewBox ?? $"0 0 {width} {height}";
        _ariaLabel = ariaLabel;
        _title = title;
    }

    public void Begin()
    {
        _sb.AppendLine($"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="{_viewBox}" width="{_width}" height="{_height}" role="img" aria-label="{SvgXml.EscapeAttr(_ariaLabel)}">""");
        _sb.AppendLine($"  <title>{SvgXml.EscapeText(_title)}</title>");
    }

    public void AppendRaw(string line) => _sb.AppendLine(line);

    public void AppendDefs(Action<StringBuilder> writeDefs)
    {
        _sb.AppendLine("  <defs>");
        writeDefs(_sb);
        _sb.AppendLine("  </defs>");
    }

    public void BeginGroup(string id, string? extraAttributes = null)
    {
        _sb.AppendLine(extraAttributes is null
            ? $"""  <g id="{SvgXml.EscapeAttr(id)}">"""
            : $"""  <g id="{SvgXml.EscapeAttr(id)}" {extraAttributes}>""");
    }

    public void EndGroup() => _sb.AppendLine("  </g>");

    public void AppendShape(SvgShape shape, bool includeIds = true)
    {
        if (includeIds)
        {
            _sb.AppendLine(
                $"""    <path id="{SvgXml.EscapeAttr(shape.Id)}" data-kind="{SvgXml.EscapeAttr(shape.Kind)}" data-label="{SvgXml.EscapeAttr(shape.Label)}" fill="{SvgXml.EscapeAttr(shape.Fill)}" d="{shape.PathData}"/>""");
        }
        else
        {
            _sb.AppendLine(
                $"""    <path data-label="{SvgXml.EscapeAttr(shape.Label)}" fill="{SvgXml.EscapeAttr(shape.Fill)}" d="{shape.PathData}"/>""");
        }
    }

    public void AppendPath(string d, string? cssClass = null, string? dataLabel = null, string? fill = null)
    {
        var attrs = new List<string>();
        if (cssClass is not null) attrs.Add($"class=\"{SvgXml.EscapeAttr(cssClass)}\"");
        if (dataLabel is not null) attrs.Add($"data-label=\"{SvgXml.EscapeAttr(dataLabel)}\"");
        if (fill is not null) attrs.Add($"fill=\"{SvgXml.EscapeAttr(fill)}\"");
        attrs.Add($"d=\"{d}\"");
        _sb.AppendLine($"    <path {string.Join(' ', attrs)}/>");
    }

    public void AppendText(string content, int x, int y, string attributes)
    {
        _sb.AppendLine($"    <text x=\"{x}\" y=\"{y}\" {attributes}>{SvgXml.EscapeText(content)}</text>");
    }

    public void AppendCircle(int cx, int cy, int r, string cssClass, string dataLabel)
    {
        _sb.AppendLine(
            $"""    <circle class="{SvgXml.EscapeAttr(cssClass)}" data-label="{SvgXml.EscapeAttr(dataLabel)}" cx="{cx}" cy="{cy}" r="{r}"/>""");
    }

    public void AppendImage(string href, int width, int height, double opacity)
    {
        _sb.AppendLine(
            $"""    <image id="raster-reference" width="{width}" height="{height}" href="{SvgXml.EscapeAttr(href)}" opacity="{opacity.ToString(System.Globalization.CultureInfo.InvariantCulture)}"/>""");
    }

    public string Finish()
    {
        _sb.AppendLine("</svg>");
        return _sb.ToString();
    }
}

static class SvgXml
{
    public static string EscapeText(string value) =>
        value
            .Replace("&", "&amp;", StringComparison.Ordinal)
            .Replace("<", "&lt;", StringComparison.Ordinal)
            .Replace(">", "&gt;", StringComparison.Ordinal);

    public static string EscapeAttr(string value) =>
        EscapeText(value).Replace("\"", "&quot;", StringComparison.Ordinal);

    public static void WriteLinearGradient(StringBuilder sb, string id, int x1, int y1, int x2, int y2, params (double offset, string color)[] stops)
    {
        sb.AppendLine($"""    <linearGradient id="{id}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" gradientUnits="userSpaceOnUse">""");
        foreach (var (offset, color) in stops)
        {
            sb.AppendLine($"""      <stop offset="{offset.ToString(System.Globalization.CultureInfo.InvariantCulture)}" stop-color="{color}"/>""");
        }
        sb.AppendLine("    </linearGradient>");
    }
}

static class SvgOverlay
{
    public const string StyleBlock = """
      <style>
        .shape-outline { fill: none; stroke: #ff2bd6; stroke-width: 2.5; stroke-linejoin: round; stroke-linecap: round; vector-effect: non-scaling-stroke; }
        .point { fill: #ffe66d; stroke: #101522; stroke-width: 2; vector-effect: non-scaling-stroke; }
        .point-label { fill: #fff9d6; font: 18px Consolas, 'Cascadia Mono', monospace; paint-order: stroke; stroke: #101522; stroke-width: 4; stroke-linejoin: round; }
        .shape-label { fill: #ffffff; font: 22px Consolas, 'Cascadia Mono', monospace; paint-order: stroke; stroke: #101522; stroke-width: 5; stroke-linejoin: round; }
      </style>
""";

    public static IEnumerable<Vec> ControlPoints(VectorPath path)
    {
        var points = path.Points.ToList();
        if (points.Count > 1 && points[^1] == points[0])
        {
            points.RemoveAt(points.Count - 1);
        }

        return points;
    }

    public static string PointLabel(string shapeLabel, int pointIndex) => $"{shapeLabel}:{pointIndex + 1}";
}

// =============================================================================
// Library: Brand model — Novolis mark geometry (six canonical shapes)
// =============================================================================

static class NovolisBrandCanvas
{
    public const int Width = 1254;
    public const int Height = 1254;
    public const int AlphaThreshold = 16;

    // Mark bounding box for icon/social cropping (approximate, includes star).
    public const int MarkMinX = 350;
    public const int MarkMinY = 200;
    public const int MarkWidth = 580;
    public const int MarkHeight = 560;
}

static class NovolisLogoMark
{
    private const int SwirlInnerRadius = 255;
    private const int SwirlOuterRadius = 265;
    private const int StarArcRadius = 44;

    public static IReadOnlyList<SvgShape> BuildShapes()
    {
        var upperLeftInner = P(413, 313);
        var upperLeftCorner = P(456, 313);
        var upperRightTip = P(850, 332);

        var leftTopInner = P(428, 357);
        var leftBottomOuter = P(526, 732);

        var rightTopOuter = P(871, 368);
        var rightBottomOuter = P(827, 671);

        var lowerRightOuter = P(810, 688);
        var lowerRightInner = P(768, 688);
        var lowerLeftInner = P(520, 711);

        var diagonalTopLeft = P(398, 326);
        var diagonalTopRight = P(531, 326);
        var diagonalShoulder = P(824, 619);
        var diagonalBottomLeft = P(731, 671);
        var diagonalLeftReturn = leftTopInner;

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
        var starRight = P(918, 285);
        var starBottom = P(874, 329);
        var starLeft = P(831, 285);

        return
        [
            new("upper", "arc-sector", "upper", "url(#mark-cyan)",
                Path(upperLeftInner)
                    .HorizontalTo(upperLeftCorner.X)
                    .ArcTo(SwirlInnerRadius, SwirlInnerRadius, largeArc: false, sweep: true, upperRightTip)
                    .ArcTo(SwirlOuterRadius, SwirlOuterRadius, largeArc: false, sweep: false, upperLeftInner)
                    .Close()),

            new("lower", "arc-sector", "lower", "url(#mark-lower)",
                Path(lowerLeftInner)
                    .ArcTo(SwirlInnerRadius, SwirlInnerRadius, largeArc: false, sweep: false, lowerRightOuter)
                    .LineTo(lowerRightInner)
                    .ArcTo(SwirlOuterRadius, SwirlOuterRadius, largeArc: false, sweep: true, lowerLeftInner)
                    .Close()),

            new("n", "line-arc", "n", "url(#mark-diagonal)",
                Path(diagonalTopLeft)
                    .HorizontalTo(diagonalTopRight.X)
                    .LineTo(diagonalShoulder)
                    .ArcTo(SwirlOuterRadius, SwirlOuterRadius, largeArc: false, sweep: false, rightTopOuter)
                    .ArcTo(SwirlInnerRadius, SwirlInnerRadius, largeArc: false, sweep: true, rightBottomOuter)
                    .HorizontalTo(diagonalBottomLeft.X)
                    .LineTo(diagonalLeftReturn)
                    .ArcTo(SwirlOuterRadius, SwirlOuterRadius, largeArc: false, sweep: false, leftBottomOuter)
                    .ArcTo(SwirlInnerRadius, SwirlInnerRadius, largeArc: false, sweep: true, diagonalTopLeft)
                    .Close()),

            new("n_left", "straight", "n_left", "url(#mark-left-stem)",
                Path(leftStemTop)
                    .LineTo(leftStemShoulder)
                    .VerticalTo(leftStemLowerRight.Y)
                    .LineTo(leftStemFoot)
                    .HorizontalTo(leftStemLowerLeft.X)
                    .Close()),

            new("n_right", "straight", "n_right", "url(#mark-right-stem)",
                Path(rightStemTopLeft)
                    .LineTo(rightStemCap)
                    .HorizontalTo(rightStemTopRight.X)
                    .VerticalTo(rightStemBottomRight.Y)
                    .LineTo(rightStemBottomLeft)
                    .Close()),

            new("star", "four-arc", "star", "url(#star-gradient)",
                Path(starTop)
                    .ArcTo(StarArcRadius, StarArcRadius, largeArc: false, sweep: false, starRight)
                    .ArcTo(StarArcRadius, StarArcRadius, largeArc: false, sweep: false, starBottom)
                    .ArcTo(StarArcRadius, StarArcRadius, largeArc: false, sweep: false, starLeft)
                    .ArcTo(StarArcRadius, StarArcRadius, largeArc: false, sweep: false, starTop)
                    .Close()),
        ];
    }

    private static Vec P(int x, int y) => new(x, y);

    private static VectorPath Path(Vec start) => VectorPath.Start(start);
}

static class NovolisBrandGradients
{
    public static void WriteMarkGradients(StringBuilder sb)
    {
        SvgXml.WriteLinearGradient(sb, "mark-cyan", 412, 206, 850, 332, (0, "#2fdfff"), (1, "#0997ff"));
        SvgXml.WriteLinearGradient(sb, "mark-left", 314, 326, 430, 639, (0, "#12c7ff"), (1, "#237cff"));
        SvgXml.WriteLinearGradient(sb, "mark-right", 871, 368, 824, 674, (0, "#2f8cff"), (1, "#8f37ff"));
        SvgXml.WriteLinearGradient(sb, "mark-lower", 526, 714, 812, 687, (0, "#7a42ff"), (1, "#b246ff"));
        SvgXml.WriteLinearGradient(sb, "mark-diagonal", 405, 327, 854, 671, (0, "#16cfff"), (0.52, "#4d86ff"), (1, "#9c42ff"));
        SvgXml.WriteLinearGradient(sb, "mark-left-stem", 472, 433, 540, 656, (0, "#0ba8ff"), (1, "#0677d9"));
        SvgXml.WriteLinearGradient(sb, "mark-right-stem", 734, 325, 804, 581, (0, "#2aa5ff"), (1, "#6138d9"));
        SvgXml.WriteLinearGradient(sb, "star-gradient", 831, 241, 918, 329, (0, "#35d8ff"), (1, "#9b60ff"));
    }

    public static void WriteLockupGradients(StringBuilder sb)
    {
        WriteMarkGradients(sb);
        SvgXml.WriteLinearGradient(sb, "tagline-gradient", 203, 967, 1051, 999, (0, "#08bfff"), (0.52, "#7547ff"), (1, "#1a8dff"));
        sb.AppendLine("""    <filter id="wordmark-glow" x="-5%" y="-20%" width="110%" height="150%">""");
        sb.AppendLine("""      <feDropShadow dx="0" dy="2" stdDeviation="1.2" flood-color="#2f8cff" flood-opacity="0.45"/>""");
        sb.AppendLine("    </filter>");
    }
}

static class NovolisBrandTypography
{
    public const string WordmarkFont =
        "Consolas, 'Cascadia Mono', 'Courier New', monospace";

    public static void AppendWordmark(SvgDocument doc)
    {
        doc.BeginGroup("vector-wordmark", $"font-family=\"{WordmarkFont}\" text-anchor=\"start\"");
        doc.AppendText(
            "NOVOLIS",
            161,
            912,
            "font-size=\"133\" font-weight=\"700\" fill=\"#f7fbff\" textLength=\"936\" lengthAdjust=\"spacingAndGlyphs\" filter=\"url(#wordmark-glow)\"");
        doc.AppendText(
            "BUILD • CREATE • EXPLORE",
            203,
            999,
            "font-size=\"35\" font-weight=\"700\" fill=\"url(#tagline-gradient)\" textLength=\"848\" lengthAdjust=\"spacingAndGlyphs\"");
        doc.EndGroup();
    }
}

// =============================================================================
// Library: Asset recipes — compose documents from the brand model
// =============================================================================

static class BrandAssetRecipes
{
    public static string FullLockup(IReadOnlyList<SvgShape> shapes, int alphaThreshold)
    {
        var doc = new SvgDocument(
            NovolisBrandCanvas.Width,
            NovolisBrandCanvas.Height,
            "Novolis",
            "Novolis vector logo");
        doc.Begin();
        doc.AppendDefs(NovolisBrandGradients.WriteLockupGradients);
        doc.BeginGroup("vector-mark", $"data-alpha-threshold=\"{alphaThreshold}\"");
        foreach (var shape in shapes)
        {
            doc.AppendShape(shape);
        }

        doc.EndGroup();
        NovolisBrandTypography.AppendWordmark(doc);
        return doc.Finish();
    }

    public static string MarkOnly(IReadOnlyList<SvgShape> shapes)
    {
        var doc = new SvgDocument(
            NovolisBrandCanvas.Width,
            NovolisBrandCanvas.Height,
            "Novolis mark",
            "Novolis mark");
        doc.Begin();
        doc.AppendDefs(NovolisBrandGradients.WriteMarkGradients);
        doc.BeginGroup("vector-mark");
        foreach (var shape in shapes)
        {
            doc.AppendShape(shape);
        }

        doc.EndGroup();
        return doc.Finish();
    }

    public static string SingleShape(SvgShape shape)
    {
        var doc = new SvgDocument(
            NovolisBrandCanvas.Width,
            NovolisBrandCanvas.Height,
            $"Novolis {shape.Label}",
            $"Novolis shape {shape.Label}");
        doc.Begin();
        doc.AppendDefs(NovolisBrandGradients.WriteMarkGradients);
        doc.BeginGroup("vector-mark");
        doc.AppendShape(shape);
        doc.EndGroup();
        return doc.Finish();
    }

    public static string Overlay(
        IReadOnlyList<SvgShape> shapes,
        string rasterReferenceHref,
        int alphaThreshold)
    {
        var doc = new SvgDocument(
            NovolisBrandCanvas.Width,
            NovolisBrandCanvas.Height,
            "Novolis logo construction overlay",
            "Novolis logo construction overlay");
        doc.Begin();
        doc.AppendRaw(SvgOverlay.StyleBlock);
        doc.AppendImage(rasterReferenceHref, NovolisBrandCanvas.Width, NovolisBrandCanvas.Height, 0.42);
        doc.BeginGroup("vector-shapes", $"data-alpha-threshold=\"{alphaThreshold}\" opacity=\"0.55\"");
        foreach (var shape in shapes)
        {
            doc.AppendShape(shape, includeIds: false);
        }

        doc.EndGroup();
        doc.BeginGroup("shape-outlines");
        foreach (var shape in shapes)
        {
            doc.AppendPath(shape.PathData, cssClass: "shape-outline", dataLabel: shape.Label);
        }

        doc.EndGroup();
        doc.BeginGroup("control-points");
        foreach (var shape in shapes)
        {
            var points = SvgOverlay.ControlPoints(shape.Path).ToList();
            for (var i = 0; i < points.Count; i++)
            {
                var point = points[i];
                var label = SvgOverlay.PointLabel(shape.Label, i);
                doc.AppendCircle(point.X, point.Y, 6, "point", label);
                doc.AppendText(label, point.X + 9, point.Y - 9, "class=\"point-label\"");
            }

            if (points.Count > 0)
            {
                var anchor = points[0];
                doc.AppendText(shape.Label, anchor.X + 18, anchor.Y + 25, "class=\"shape-label\"");
            }
        }

        doc.EndGroup();
        return doc.Finish();
    }

    public static string IconMark(IReadOnlyList<SvgShape> shapes, int size = 512)
    {
        var viewBox = $"{NovolisBrandCanvas.MarkMinX} {NovolisBrandCanvas.MarkMinY} {NovolisBrandCanvas.MarkWidth} {NovolisBrandCanvas.MarkHeight}";
        var doc = new SvgDocument(size, size, "Novolis icon", "Novolis icon mark", viewBox);
        doc.Begin();
        doc.AppendDefs(NovolisBrandGradients.WriteMarkGradients);
        doc.BeginGroup("vector-mark");
        foreach (var shape in shapes)
        {
            doc.AppendShape(shape);
        }

        doc.EndGroup();
        return doc.Finish();
    }

    public static string SocialCard(IReadOnlyList<SvgShape> shapes, int width = 1200, int height = 630)
    {
        var doc = new SvgDocument(width, height, "Novolis social card", "Novolis social card");
        doc.Begin();
        doc.AppendRaw("  <rect width=\"100%\" height=\"100%\" fill=\"#05070d\"/>");
        doc.AppendDefs(NovolisBrandGradients.WriteLockupGradients);
        var markScale = 0.62;
        var markOffsetX = 80;
        var markOffsetY = 20;
        doc.BeginGroup(
            "vector-mark",
            $"transform=\"translate({markOffsetX} {markOffsetY}) scale({markScale.ToString(System.Globalization.CultureInfo.InvariantCulture)})\"");
        foreach (var shape in shapes)
        {
            doc.AppendShape(shape);
        }

        doc.EndGroup();
        doc.BeginGroup(
            "vector-wordmark",
            $"font-family=\"{NovolisBrandTypography.WordmarkFont}\" transform=\"translate(720 250) scale(0.55)\"");
        doc.AppendText(
            "NOVOLIS",
            0,
            0,
            "font-size=\"133\" font-weight=\"700\" fill=\"#f7fbff\" filter=\"url(#wordmark-glow)\"");
        doc.AppendText(
            "BUILD • CREATE • EXPLORE",
            42,
            87,
            "font-size=\"35\" font-weight=\"700\" fill=\"url(#tagline-gradient)\"");
        doc.EndGroup();
        return doc.Finish();
    }
}

// =============================================================================
// Library: Image bridge — SVG to PNG via external renderer (adapter boundary)
// =============================================================================

static class SvgRasterBridge
{
    public static int RenderToPng(string svgPath, string pngPath, int? fitWidth = null, int? fitHeight = null)
    {
        var args = new List<string> { svgPath, pngPath };
        if (fitWidth is not null)
        {
            args.Add("--fit-width");
            args.Add(fitWidth.Value.ToString());
        }

        if (fitHeight is not null)
        {
            args.Add("--fit-height");
            args.Add(fitHeight.Value.ToString());
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "npx",
            Arguments = "--yes @resvg/resvg-js-cli " + string.Join(' ', args.Select(a => $"\"{a}\"")),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Failed to start npx resvg renderer.");
        process.WaitForExit();
        if (process.ExitCode != 0)
        {
            var err = process.StandardError.ReadToEnd();
            throw new InvalidOperationException($"SVG render failed ({process.ExitCode}): {err}");
        }

        return process.ExitCode;
    }
}

// =============================================================================
// App — command dispatch, output paths, verification
// =============================================================================

static class BrandLogoApp
{
    private static readonly string[] CanonicalShapeNames =
        ["upper", "lower", "n", "n_left", "n_right", "star"];

    public static int Run(string[] args)
    {
        var command = ResolveCommand(args, out var outputDir, out var rasterPng, out var alphaThreshold);
        var shapes = NovolisLogoMark.BuildShapes();
        Directory.CreateDirectory(outputDir);
        Directory.CreateDirectory(Path.Combine(outputDir, "generated", "shapes"));

        var written = new List<string>();

        switch (command)
        {
            case "full":
                written.Add(WriteFull(outputDir, shapes, alphaThreshold));
                written.Add(WriteOverlay(outputDir, shapes, rasterPng, alphaThreshold));
                break;
            case "overlay":
                written.Add(WriteOverlay(outputDir, shapes, rasterPng, alphaThreshold));
                break;
            case "mark":
                written.Add(WriteMark(outputDir, shapes));
                break;
            case "shapes":
                written.AddRange(WritePerShape(outputDir, shapes));
                break;
            case "icon":
                written.Add(WriteIcon(outputDir, shapes));
                break;
            case "social":
                written.Add(WriteSocial(outputDir, shapes));
                break;
            case "png":
                written.AddRange(WriteAllSvgVariants(outputDir, shapes, rasterPng, alphaThreshold));
                RenderPngOutputs(outputDir);
                break;
            case "verify":
                written.AddRange(WriteAllSvgVariants(outputDir, shapes, rasterPng, alphaThreshold));
                return BrandAssetVerifier.Verify(outputDir, shapes) ? 0 : 1;
            case "all":
            default:
                written.AddRange(WriteAllSvgVariants(outputDir, shapes, rasterPng, alphaThreshold));
                break;
        }

        foreach (var path in written)
        {
            Console.WriteLine($"Wrote {path}");
        }

        Console.WriteLine($"Shapes: {shapes.Count}");
        Console.WriteLine($"Command: {command}");
        return 0;
    }

    private static string ResolveCommand(string[] args, out string outputDir, out string rasterPng, out int alphaThreshold)
    {
        outputDir = Directory.GetCurrentDirectory();
        rasterPng = "logo-brand-transparent.png";
        alphaThreshold = NovolisBrandCanvas.AlphaThreshold;

        if (args.Length == 0)
        {
            return "all";
        }

        if (args[0].Equals("verify", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("all", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("full", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("overlay", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("mark", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("shapes", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("icon", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("social", StringComparison.OrdinalIgnoreCase) ||
            args[0].Equals("png", StringComparison.OrdinalIgnoreCase))
        {
            return args[0].ToLowerInvariant();
        }

        // Legacy positional: [png] [output.svg] [threshold]
        if (args.Length >= 2 && args[1].EndsWith(".svg", StringComparison.OrdinalIgnoreCase))
        {
            rasterPng = args[0];
            outputDir = Path.GetDirectoryName(Path.GetFullPath(args[1])) ?? outputDir;
            if (args.Length >= 3 && int.TryParse(args[2], out var parsed))
            {
                alphaThreshold = parsed;
            }

            return "full";
        }

        return args[0].ToLowerInvariant();
    }

    private static IEnumerable<string> WriteAllSvgVariants(
        string outputDir,
        IReadOnlyList<SvgShape> shapes,
        string rasterPng,
        int alphaThreshold)
    {
        yield return WriteFull(outputDir, shapes, alphaThreshold);
        yield return WriteOverlay(outputDir, shapes, rasterPng, alphaThreshold);
        yield return WriteMark(outputDir, shapes);
        foreach (var path in WritePerShape(outputDir, shapes))
        {
            yield return path;
        }

        yield return WriteIcon(outputDir, shapes);
        yield return WriteSocial(outputDir, shapes);
    }

    private static string WriteFull(string outputDir, IReadOnlyList<SvgShape> shapes, int alphaThreshold)
    {
        var path = Path.Combine(outputDir, "logo-brand-transparent.svg");
        File.WriteAllText(path, BrandAssetRecipes.FullLockup(shapes, alphaThreshold), Encoding.UTF8);
        return path;
    }

    private static string WriteOverlay(
        string outputDir,
        IReadOnlyList<SvgShape> shapes,
        string rasterPng,
        int alphaThreshold)
    {
        var path = Path.Combine(outputDir, "logo-brand-transparent-overlay.svg");
        var href = Path.GetRelativePath(outputDir, Path.GetFullPath(rasterPng)).Replace('\\', '/');
        File.WriteAllText(path, BrandAssetRecipes.Overlay(shapes, href, alphaThreshold), Encoding.UTF8);
        return path;
    }

    private static string WriteMark(string outputDir, IReadOnlyList<SvgShape> shapes)
    {
        var path = Path.Combine(outputDir, "generated", "logo-mark.svg");
        File.WriteAllText(path, BrandAssetRecipes.MarkOnly(shapes), Encoding.UTF8);
        return path;
    }

    private static IEnumerable<string> WritePerShape(string outputDir, IReadOnlyList<SvgShape> shapes)
    {
        foreach (var shape in shapes)
        {
            var path = Path.Combine(outputDir, "generated", "shapes", $"{shape.Label}.svg");
            File.WriteAllText(path, BrandAssetRecipes.SingleShape(shape), Encoding.UTF8);
            yield return path;
        }
    }

    private static string WriteIcon(string outputDir, IReadOnlyList<SvgShape> shapes)
    {
        var path = Path.Combine(outputDir, "generated", "logo-icon.svg");
        File.WriteAllText(path, BrandAssetRecipes.IconMark(shapes), Encoding.UTF8);
        return path;
    }

    private static string WriteSocial(string outputDir, IReadOnlyList<SvgShape> shapes)
    {
        var path = Path.Combine(outputDir, "generated", "logo-social.svg");
        File.WriteAllText(path, BrandAssetRecipes.SocialCard(shapes), Encoding.UTF8);
        return path;
    }

    private static void RenderPngOutputs(string outputDir)
    {
        var pngTargets = new (string Svg, string Png, int? W, int? H)[]
        {
            (Path.Combine(outputDir, "logo-brand-transparent.svg"), Path.Combine(outputDir, "generated", "logo-brand-transparent.png"), NovolisBrandCanvas.Width, NovolisBrandCanvas.Height),
            (Path.Combine(outputDir, "generated", "logo-mark.svg"), Path.Combine(outputDir, "generated", "logo-mark.png"), NovolisBrandCanvas.Width, NovolisBrandCanvas.Height),
            (Path.Combine(outputDir, "generated", "logo-icon.svg"), Path.Combine(outputDir, "generated", "logo-icon.png"), 512, 512),
            (Path.Combine(outputDir, "generated", "logo-social.svg"), Path.Combine(outputDir, "generated", "logo-social.png"), 1200, 630),
        };

        Directory.CreateDirectory(Path.Combine(outputDir, "generated"));
        foreach (var (svg, png, w, h) in pngTargets)
        {
            if (!File.Exists(svg))
            {
                continue;
            }

            SvgRasterBridge.RenderToPng(svg, png, w, h);
            Console.WriteLine($"Rendered {png}");
        }
    }
}

static class BrandAssetVerifier
{
    public static bool Verify(string outputDir, IReadOnlyList<SvgShape> shapes)
    {
        var ok = true;
        ok &= CheckFileContainsAll(
            Path.Combine(outputDir, "logo-brand-transparent.svg"),
            shapes.Select(s => $"data-label=\"{s.Label}\"").Append("NOVOLIS"));
        ok &= CheckFileContainsAll(
            Path.Combine(outputDir, "logo-brand-transparent-overlay.svg"),
            ["n:1", "star:4", "upper:1", "lower:1"]);
        ok &= CheckFileContainsAll(
            Path.Combine(outputDir, "generated", "logo-mark.svg"),
            shapes.Select(s => $"data-label=\"{s.Label}\""));
        ok &= CheckFileMissing(
            Path.Combine(outputDir, "generated", "logo-mark.svg"),
            ["NOVOLIS", "BUILD • CREATE • EXPLORE"]);

        foreach (var shape in shapes)
        {
            var shapePath = Path.Combine(outputDir, "generated", "shapes", $"{shape.Label}.svg");
            ok &= File.Exists(shapePath);
            ok &= CheckFileContainsAll(shapePath, [$"data-label=\"{shape.Label}\""]);
        }

        Console.WriteLine(ok ? "verify: OK" : "verify: FAILED");
        return ok;
    }

    private static bool CheckFileContainsAll(string path, IEnumerable<string> needles)
    {
        if (!File.Exists(path))
        {
            Console.Error.WriteLine($"Missing file: {path}");
            return false;
        }

        var text = File.ReadAllText(path);
        foreach (var needle in needles)
        {
            if (!text.Contains(needle, StringComparison.Ordinal))
            {
                Console.Error.WriteLine($"Expected '{needle}' in {path}");
                return false;
            }
        }

        return true;
    }

    private static bool CheckFileMissing(string path, IEnumerable<string> needles)
    {
        if (!File.Exists(path))
        {
            Console.Error.WriteLine($"Missing file: {path}");
            return false;
        }

        var text = File.ReadAllText(path);
        foreach (var needle in needles)
        {
            if (text.Contains(needle, StringComparison.Ordinal))
            {
                Console.Error.WriteLine($"Did not expect '{needle}' in {path}");
                return false;
            }
        }

        return true;
    }
}
