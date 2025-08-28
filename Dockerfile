//#define USE_TESSERACT
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using OpenCvSharp;

#if USE_TESSERACT
using Tesseract;
#endif

namespace HighAccuracyOMR
{
    class OMRConfig
    {
        // --- Detection params (tune for your DPI) ---
        public int MinBubbleArea = 250;        // px
        public int MaxBubbleArea = 30000;      // px
        public double MinAspectRatio = 0.40;   // accept tall ovals
        public double MaxAspectRatio = 2.8;    // accept wide ovals/rects
        public double MinCircularity = 0.25;   // 1.0=circle; allow low for squares/ovals

        // --- Preprocessing ---
        public int IlluminationKernel = 41;    // odd; background blur for division
        public int AdaptiveBlock = 35;         // odd; local threshold window
        public int AdaptiveC = 10;             // bias for adaptive threshold

        // --- Row grouping ---
        public int RowMergeTolerance = 14;     // px; increase if rows jitter vertically

        // --- Decision logic ---
        public bool AllowMultiple = true;      // allow multiple selections per row
        public double MinFilledRatio = 0.10;   // minimal interior ink ratio to consider as filled candidate
        public double SinglePickMargin = 0.18; // top must beat second by >=18%
        public double MultiRelToTop = 0.85;    // multi: pick any >=85% of top

        // --- Debug ---
        public string DebugDir = "debug";      // folder for QA overlays
        public bool SavePerRowOverlays = false;
    }

    class Bubble
    {
        public Rect BBox;
        public double Area;
        public double Aspect;
        public double Circularity;
        public Point2f Center => new Point2f(BBox.X + BBox.Width / 2f, BBox.Y + BBox.Height / 2f);

        // Metrics
        public double InkRatio;       // white pixels ratio after local Otsu (BinaryInv)
        public double InteriorRatio;  // after erode (reduces outline influence)
        public double Mean;           // mean gray intensity (0..255)
        public double LocalOtsu;      // local Otsu threshold

        // Decision
        public bool IsSelected;
        public double Confidence;     // 0..1 row-relative confidence
        public char ChoiceLetter;     // A,B,C,... assigned later
    }

    class Row
    {
        public List<Bubble> Bubbles = new();
        public int QuestionIndex; // 1-based when ordered by Y; may be replaced by OCR mapping

        public List<Bubble> Selected = new();
        public string Flags = string.Empty; // "AMBIG";"LOWCONF";"MULTI"
        public double TopScore;
        public double SecondScore;
    }

    class Program
    {
        static int Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.WriteLine("Usage: dotnet run -- <scanPath> <outCsv> [templatePath] [--tessdata ./tessdata]");
                return 1;
            }

            string scanPath = args[0];
            string outCsv = args[1];
            string? templatePath = null;
            string? tessData = null;

            for (int i = 2; i < args.Length; i++)
            {
                if (args[i].StartsWith("--tessdata"))
                {
                    var parts = args[i].Split(' ', '=', 2, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length == 2) tessData = parts[1];
                    else if (i + 1 < args.Length) { tessData = args[i + 1]; i++; }
                }
                else if (templatePath == null)
                {
                    templatePath = args[i];
                }
            }

            if (!File.Exists(scanPath)) { Console.WriteLine($"Scan not found: {scanPath}"); return 2; }
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outCsv)) ?? ".");

            var cfg = new OMRConfig();
            Directory.CreateDirectory(cfg.DebugDir);

            using var srcColor = Cv2.ImRead(scanPath, ImreadModes.Color);
            if (srcColor.Empty()) { Console.WriteLine("Failed to read scan"); return 3; }

            Mat aligned = (templatePath != null && File.Exists(templatePath))
                ? AlignToTemplate(srcColor, templatePath)
                : DeskewAndRectify(srcColor);

            Mat grayEq, binary;
            Preprocess(aligned, cfg, out grayEq, out binary);

            var candidates = FindBubbleCandidates(binary, cfg);
            if (candidates.Count == 0)
            {
                Console.WriteLine("No bubble candidates found. Tune Min/MaxBubbleArea and preprocessing.");
                return 4;
            }

            ComputeFillMetrics(candidates, grayEq);

            var rows = GroupIntoRows(candidates, cfg.RowMergeTolerance);

            foreach (var row in rows)
                for (int i = 0; i < row.Bubbles.Count; i++)
                    row.Bubbles[i].ChoiceLetter = (char)('A' + i);

            foreach (var row in rows)
                DecideRow(row, cfg);

#if USE_TESSERACT
            if (!string.IsNullOrWhiteSpace(tessData))
            {
                try
                {
                    MapQuestionNumbersWithOCR(rows, aligned, tessData);
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[OCR] Skipped due to: " + ex.Message);
                }
            }
#endif

            WriteCsv(outCsv, rows);
            DrawDebug(aligned, rows, cfg);

            Console.WriteLine($"Done. Rows: {rows.Count}. CSV: {outCsv}. Debug in {cfg.DebugDir}.");
            return 0;
        }

        // ==================== Alignment ====================
        static Mat AlignToTemplate(Mat src, string templatePath)
        {
            using var templ = Cv2.ImRead(templatePath, ImreadModes.Color);
            if (templ.Empty()) return src.Clone();

            using var srcGray = new Mat(); using var tmpGray = new Mat();
            Cv2.CvtColor(src, srcGray, ColorConversionCodes.BGR2GRAY);
            Cv2.CvtColor(templ, tmpGray, ColorConversionCodes.BGR2GRAY);

            var orb = ORB.Create(6000);
            orb.DetectAndCompute(srcGray, null, out KeyPoint[] kp1, out Mat des1);
            orb.DetectAndCompute(tmpGray, null, out KeyPoint[] kp2, out Mat des2);
            if (des1.Empty() || des2.Empty()) return src.Clone();

            using var bf = new BFMatcher(NormTypes.Hamming, crossCheck: true);
            var matches = bf.Match(des1, des2);
            if (matches.Length < 20) return src.Clone();
            var good = matches.OrderBy(m => m.Distance).Take(Math.Max(30, matches.Length / 5)).ToArray();

            var pts1 = good.Select(m => kp1[m.QueryIdx].Pt).Select(p => new Point2f(p.X, p.Y)).ToArray();
            var pts2 = good.Select(m => kp2[m.TrainIdx].Pt).Select(p => new Point2f(p.X, p.Y)).ToArray();
            var H = Cv2.FindHomography(InputArray.Create(pts1), InputArray.Create(pts2), HomographyMethods.Ransac, 3);
            if (H.Empty()) return src.Clone();

            var warped = new Mat();
            Cv2.WarpPerspective(src, warped, H, templ.Size());
            return warped;
        }

        static Mat DeskewAndRectify(Mat src)
        {
            using var gray = new Mat();
            Cv2.CvtColor(src, gray, ColorConversionCodes.BGR2GRAY);
            Cv2.GaussianBlur(gray, gray, new Size(5, 5), 0);
            using var edges = new Mat();
            Cv2.Canny(gray, edges, 50, 150);

            Cv2.FindContours(edges, out var contours, out _, RetrievalModes.List, ContourApproximationModes.ApproxSimple);
            var candidate = contours
                .Select(c => new { C = c, Area = Cv2.ContourArea(c) })
                .OrderByDescending(x => x.Area)
                .Take(10)
                .Select(x => new { x.Area, Approx = Cv2.ApproxPolyDP(x.C, 0.02 * Cv2.ArcLength(x.C, true), true) })
                .FirstOrDefault(x => x.Approx.Length == 4);

            if (candidate != null)
            {
                var pts = candidate.Approx.Select(p => new Point2f(p.X, p.Y)).ToArray();
                var ordered = OrderQuadPoints(pts);
                float widthA = Dist(ordered[2], ordered[3]);
                float widthB = Dist(ordered[1], ordered[0]);
                float maxW = Math.Max(widthA, widthB);
                float heightA = Dist(ordered[1], ordered[2]);
                float heightB = Dist(ordered[0], ordered[3]);
                float maxH = Math.Max(heightA, heightB);

                var dst = new[] { new Point2f(0, 0), new Point2f(maxW - 1, 0), new Point2f(maxW - 1, maxH - 1), new Point2f(0, maxH - 1) };
                var M = Cv2.GetPerspectiveTransform(ordered, dst);
                var warped = new Mat();
                Cv2.WarpPerspective(src, warped, M, new Size((int)maxW, (int)maxH));
                return warped;
            }

            // Fallback: estimate global skew via Hough lines and rotate
            using var bw = new Mat();
            Cv2.Threshold(gray, bw, 0, 255, ThresholdTypes.Otsu | ThresholdTypes.Binary);
            using var inv = new Mat();
            Cv2.BitwiseNot(bw, inv);
            var lines = Cv2.HoughLines(inv, 1, Math.PI / 180, 200);
            double angle = 0; int count = 0;
            if (lines != null)
            {
                foreach (var l in lines)
                {
                    double theta = l.Theta * 180.0 / Math.PI;
                    if (theta < 10 || theta > 170) { angle += theta < 90 ? theta : theta - 180; count++; }
                }
            }
            double avg = count > 0 ? angle / count : 0;
            var center = new Point2f(src.Cols / 2f, src.Rows / 2f);
            var rot = Cv2.GetRotationMatrix2D(center, avg, 1.0);
            var rotated = new Mat();
            Cv2.WarpAffine(src, rotated, rot, src.Size(), InterpolationFlags.Cubic, BorderTypes.Replicate);
            return rotated;
        }

        static Point2f[] OrderQuadPoints(Point2f[] pts)
        {
            var sum = pts.Select(p => p.X + p.Y).ToArray();
            var diff = pts.Select(p => p.Y - p.X).ToArray();
            var tl = pts[Array.IndexOf(sum, sum.Min())];
            var br = pts[Array.IndexOf(sum, sum.Max())];
            var tr = pts[Array.IndexOf(diff, diff.Min())];
            var bl = pts[Array.IndexOf(diff, diff.Max())];
            return new[] { tl, tr, br, bl };
        }

        static float Dist(Point2f a, Point2f b)
            => (float)Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));

        // ==================== Preprocess ====================
        static void Preprocess(Mat src, OMRConfig cfg, out Mat grayEq, out Mat binary)
        {
            using var gray = new Mat();
            Cv2.CvtColor(src, gray, ColorConversionCodes.BGR2GRAY);

            // Illumination correction: divide by large-kernel blur (background)
            using var bg = new Mat();
            Cv2.GaussianBlur(gray, bg, new Size(cfg.IlluminationKernel, cfg.IlluminationKernel), 0);
            using var fGray = new Mat(); gray.ConvertTo(fGray, MatType.CV_32F);
            using var fBg = new Mat(); bg.ConvertTo(fBg, MatType.CV_32F);
            using var div = new Mat(); Cv2.Divide(fGray, fBg + 1.0, div);
            using var norm = new Mat(); Cv2.Normalize(div, norm, 0, 255, NormTypes.MinMax);
            grayEq = new Mat(); norm.ConvertTo(grayEq, MatType.CV_8U);

            // Adaptive threshold → white=ink (BinaryInv)
            binary = new Mat();
            Cv2.AdaptiveThreshold(grayEq, binary, 255, AdaptiveThresholdTypes.Gaussian, ThresholdTypes.BinaryInv, cfg.AdaptiveBlock, cfg.AdaptiveC);

            // Light denoise
            using var kernel = Cv2.GetStructuringElement(MorphShapes.Ellipse, new Size(3, 3));
            Cv2.MorphologyEx(binary, binary, MorphTypes.Open, kernel);
        }

        // ==================== Detection ====================
        static List<Bubble> FindBubbleCandidates(Mat binary, OMRConfig cfg)
        {
            Cv2.FindContours(binary, out var contours, out _, RetrievalModes.External, ContourApproximationModes.ApproxNone);
            var list = new List<Bubble>();
            foreach (var cnt in contours)
            {
                var area = Cv2.ContourArea(cnt);
                if (area < cfg.MinBubbleArea || area > cfg.MaxBubbleArea) continue;
                var rect = Cv2.BoundingRect(cnt);
                double aspect = rect.Width / (double)rect.Height;
                if (aspect < cfg.MinAspectRatio || aspect > cfg.MaxAspectRatio) continue;
                double peri = Cv2.ArcLength(cnt, true);
                if (peri <= 0) continue;
                double circ = 4 * Math.PI * area / (peri * peri);
                if (circ < cfg.MinCircularity) continue;
                list.Add(new Bubble { BBox = rect, Area = area, Aspect = aspect, Circularity = circ });
            }

            // Non-maximum suppression to dedupe overlaps
            list = NonMaxSuppress(list, 0.30);
            return list.OrderBy(b => b.Center.Y).ThenBy(b => b.Center.X).ToList();
        }

        static List<Bubble> NonMaxSuppress(List<Bubble> boxes, double iouThresh)
        {
            var keep = new List<Bubble>();
            var sorted = boxes.OrderByDescending(b => b.Area).ToList();
            while (sorted.Count > 0)
            {
                var a = sorted[0];
                keep.Add(a);
                sorted.RemoveAt(0);
                sorted = sorted.Where(b => IoU(a.BBox, b.BBox) < iouThresh).ToList();
            }
            return keep;
        }

        static double IoU(Rect a, Rect b)
        {
            int x1 = Math.Max(a.X, b.X);
            int y1 = Math.Max(a.Y, b.Y);
            int x2 = Math.Min(a.X + a.Width, b.X + b.Width);
            int y2 = Math.Min(a.Y + a.Height, b.Y + b.Height);
            int inter = Math.Max(0, x2 - x1) * Math.Max(0, y2 - y1);
            int areaA = a.Width * a.Height;
            int areaB = b.Width * b.Height;
            int uni = areaA + areaB - inter;
            return uni == 0 ? 0 : (double)inter / uni;
        }

        // ==================== Metrics ====================
        static void ComputeFillMetrics(List<Bubble> bubbles, Mat grayEq)
        {
            foreach (var b in bubbles)
            {
                using var roi = new Mat(grayEq, b.BBox);
                using var blur = new Mat(); Cv2.GaussianBlur(roi, blur, new Size(3, 3), 0);

                // Local Otsu for robust binarization
                b.LocalOtsu = Cv2.Threshold(blur, new Mat(), 0, 255, ThresholdTypes.Otsu);
                using var localBin = new Mat();
                Cv2.Threshold(blur, localBin, b.LocalOtsu, 255, ThresholdTypes.BinaryInv); // white=ink

                // Raw ink ratio
                double ink = Cv2.CountNonZero(localBin);
                b.InkRatio = ink / (b.BBox.Width * b.BBox.Height);

                // Interior emphasis: erode to kill outlines/checkmarks ghosting
                using var kernel = Cv2.GetStructuringElement(MorphShapes.Rect, new Size(3, 3));
                using var eroded = new Mat();
                Cv2.Erode(localBin, eroded, kernel, iterations: 1);
                double inkInterior = Cv2.CountNonZero(eroded);
                b.InteriorRatio = inkInterior / (b.BBox.Width * b.BBox.Height);

                // Mean gray level
                b.Mean = Cv2.Mean(roi).Val0;
            }
        }

        // ==================== Rows & Decisions ====================
        static List<Row> GroupIntoRows(List<Bubble> bubbles, int tol)
        {
            var rows = new List<Row>();
            foreach (var b in bubbles)
            {
                bool placed = false;
                foreach (var row in rows)
                {
                    if (Math.Abs(row.Bubbles[0].Center.Y - b.Center.Y) <= tol)
                    {
                        row.Bubbles.Add(b); placed = true; break;
                    }
                }
                if (!placed) rows.Add(new Row { Bubbles = new List<Bubble> { b } });
            }
            foreach (var r in rows) r.Bubbles.Sort((a, c) => a.Center.X.CompareTo(c.Center.X));
            rows = rows.OrderBy(r => r.Bubbles.Average(b => b.Center.Y)).ToList();
            for (int i = 0; i < rows.Count; i++) rows[i].QuestionIndex = i + 1;
            return rows;
        }

        static void DecideRow(Row row, OMRConfig cfg)
        {
            var scores = row.Bubbles.Select(b => b.InteriorRatio).ToArray();
            double top = scores.Max();
            int topIdx = Array.IndexOf(scores, top);
            double second = scores.OrderByDescending(s => s).Skip(1).DefaultIfEmpty(0).First();
            row.TopScore = top; row.SecondScore = second;

            if (top < cfg.MinFilledRatio)
            {
                row.Flags = AppendFlag(row.Flags, "LOWCONF");
                row.Selected.Clear();
                foreach (var b in row.Bubbles) { b.IsSelected = false; b.Confidence = 0; }
                return;
            }

            double margin = (top - second) / (top + 1e-6);
            if (margin >= cfg.SinglePickMargin)
            {
                var winner = row.Bubbles[topIdx];
                winner.IsSelected = true; winner.Confidence = Clamp01(margin);
                row.Selected = new List<Bubble> { winner };
                return;
            }

            if (cfg.AllowMultiple)
            {
                var picked = new List<Bubble>();
                foreach (var (b, s) in row.Bubbles.Zip(scores, (b, s) => (b, s)))
                {
                    if (s >= cfg.MinFilledRatio && s >= top * cfg.MultiRelToTop)
                    {
                        b.IsSelected = true;
                        b.Confidence = Clamp01((s - cfg.MinFilledRatio) / (top - cfg.MinFilledRatio + 1e-6));
                        picked.Add(b);
                    }
                    else { b.IsSelected = false; b.Confidence = 0; }
                }
                if (picked.Count > 1) row.Flags = AppendFlag(row.Flags, "MULTI");
                if (picked.Count == 0) row.Flags = AppendFlag(row.Flags, "AMBIG");
                row.Selected = picked;
            }
            else
            {
                var winner = row.Bubbles[topIdx];
                winner.IsSelected = true; winner.Confidence = Clamp01(margin);
                row.Selected = new List<Bubble> { winner };
                row.Flags = AppendFlag(row.Flags, "AMBIG");
            }
        }

        static string AppendFlag(string flags, string f)
            => string.IsNullOrEmpty(flags) ? f : (flags + ";" + f);

        static double Clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

#if USE_TESSERACT
        static void MapQuestionNumbersWithOCR(List<Row> rows, Mat aligned, string tessDataPath)
        {
            // Heuristic: assign sequential first, or customize layout mapping as needed.
            // For truly precise mapping, use Tesseract ResultIterator to read left-margin numbers with coordinates,
            // then snap each row to the closest OCR y-position.

            int h = aligned.Rows, w = aligned.Cols;
            int leftBand = (int)(w * 0.18);

            using var gray = new Mat();
            Cv2.CvtColor(aligned, gray, ColorConversionCodes.BGR2GRAY);
            using var leftRoi = new Mat(gray, new Rect(0, 0, Math.Max(1, leftBand), h));
            using var leftEq = new Mat(); Cv2.EqualizeHist(leftRoi, leftEq);

            using var ms = leftEq.ToMemoryStream(".png");
            using var engine = new TesseractEngine(tessDataPath, "eng", EngineMode.Default);
            using var pix = Pix.LoadFromMemory(ms.ToArray());
            using var page = engine.Process(pix, PageSegMode.Auto);
            string text = page.GetText();

            // Default: sequential mapping if OCR not used with coords
            int seq = 1;
            foreach (var r in rows) r.QuestionIndex = seq++;
        }
#endif

        // ==================== Output ====================
        static void WriteCsv(string outCsv, List<Row> rows)
        {
            var lines = new List<string> { "Question,Selected,Confidence,Flags" };
            foreach (var row in rows)
            {
                string selected = row.Selected.Count == 0 ? "-" : string.Join(";", row.Selected.Select(b => b.ChoiceLetter.ToString()));
                double conf = row.Selected.Count == 0 ? 0 : row.Selected.Average(b => b.Confidence);
                lines.Add(string.Join(',', new[]
                {
                    row.QuestionIndex.ToString(CultureInfo.InvariantCulture),
                    selected,
                    conf.ToString("0.000", CultureInfo.InvariantCulture),
                    row.Flags
                }));
            }
            File.WriteAllLines(outCsv, lines);
        }

        static void DrawDebug(Mat aligned, List<Row> rows, OMRConfig cfg)
        {
            var dbg = aligned.Clone();
            foreach (var (row, i) in rows.Select((r, idx) => (r, idx + 1)))
            {
                foreach (var b in row.Bubbles)
                {
                    var color = b.IsSelected ? Scalar.LimeGreen : Scalar.Red;
                    if (!b.IsSelected && row.Flags.Contains("AMBIG")) color = new Scalar(0, 165, 255); // orange
                    Cv2.Rectangle(dbg, b.BBox, color, 2);
                    Cv2.PutText(dbg, $"{b.ChoiceLetter}:{b.InteriorRatio:0.00}",
                        new Point(b.BBox.X, b.BBox.Y - 4),
                        HersheyFonts.HersheySimplex, 0.5, color, 1, LineTypes.AntiAlias);
                }
                var first = row.Bubbles.First();
                Cv2.PutText(dbg, $"Q{row.QuestionIndex}",
                    new Point(first.BBox.X - 60, first.BBox.Y + first.BBox.Height),
                    HersheyFonts.HersheySimplex, 0.7, Scalar.White, 2, LineTypes.AntiAlias);
            }

            string path = Path.Combine(cfg.DebugDir, "overlay_all.png");
            Cv2.ImWrite(path, dbg);

            if (cfg.SavePerRowOverlays)
            {
                int idx = 1;
                foreach (var row in rows)
                {
                    var box = BoundingRect(row.Bubbles.Select(b => b.BBox).ToList());
                    var pad = 20;
                    var roiRect = new Rect(Math.Max(0, box.X - pad), Math.Max(0, box.Y - pad),
                        Math.Min(aligned.Cols - (box.X - pad), box.Width + pad * 2),
                        Math.Min(aligned.Rows - (box.Y - pad), box.Height + pad * 2));
                    using var crop = new Mat(dbg, roiRect);
                    Cv2.ImWrite(Path.Combine(cfg.DebugDir, $"row_{idx:000}.png"), crop);
                    idx++;
                }
            }
        }

        static Rect BoundingRect(List<Rect> rects)
        {
            int x1 = rects.Min(r => r.X);
            int y1 = rects.Min(r => r.Y);
            int x2 = rects.Max(r => r.X + r.Width);
            int y2 = rects.Max(r => r.Y + r.Height);
            return new Rect(x1, y1, x2 - x1, y2 - y1);
        }
    }

    static class MatExtensions
    {
        public static MemoryStream ToMemoryStream(this Mat mat, string ext)
        {
            if (!ext.StartsWith(".")) ext = "." + ext;
            Cv2.ImEncode(ext, mat, out var bytes);
            return new MemoryStream(bytes);
        }
    }
}
