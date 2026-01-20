import java.util.*;
import java.io.*;

final String SEGMENT_CSV = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/UmfrageErgebnisse/Teilnehmer5/100er.Set1.1.csv";
final String IMG_DIR  = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/Umfragebogen/bilder_sets";

final String EXPORT_SUBDIR = "Visualisierungen";
final int EXPORT_W = 1920;
final int EXPORT_H = 1080;

final char SEP = ';';

final float FIX_MAX_DIST_PX = 60;
final int   FIX_MIN_MS      = 150;

final boolean HIDE_SCANPATH_INSIDE_FIXATIONS = true;
final boolean SHOW_BLINKS = true;

class Row {
  int t;
  String event;
  String payload;
  float gx, gy;
}

class GazeSample {
  int t;
  float gx, gy;
}

class Fixation {
  float x,y;
  int startT,endT;
  int dur(){ return max(0,endT-startT); }
}

class Blink {
  int startT,endT;
  int dur(){ return max(0,endT-startT); }
}

int cond = -1;
boolean isZoom = false;
int zoomFromNameIdx = -1;
int setFromNameIdx = -1;
String zoomId = null;
String[] ids = null;
String animalFolder = null;

ArrayList<Row> rows = new ArrayList<Row>();
ArrayList<GazeSample> gaze = new ArrayList<GazeSample>();
ArrayList<Blink> blinks = new ArrayList<Blink>();
ArrayList<Fixation> fixations = new ArrayList<Fixation>();

int totalT = 0;
int blinkThr = 30;

PFont font18, font28;

boolean gazeIsNormalized = true;
float gazeBaseW = 1, gazeBaseH = 1;

void settings() { size(EXPORT_W, EXPORT_H); }

void setup() {
  surface.setTitle("One Segment → One Still");

  font18 = createFont("Arial", 18);
  font28 = createFont("Arial", 28);
  textFont(font18);

  parseFilenameMeta(SEGMENT_CSV);
  loadSegmentCsv(SEGMENT_CSV);
  extractStimulusInfoFromPayload();
  detectGazeCoordinateMode();
  computeBlinks();
  computeFixations();

  PGraphics pg = createGraphics(EXPORT_W, EXPORT_H);
  pg.beginDraw();
  pg.background(20);
  pg.textFont(font18);
  pg.imageMode(CENTER);

if (isZoom) {
  drawZoomBackground(pg);
} else {
  drawSetBackground(pg);
  drawFakeNavBar(pg);
  drawFakeTitle(pg);

  if (cond == 1) {
    drawFakeButton(pg, EXPORT_W/2 - 100, EXPORT_H - 90, 200, 56, "Auswählen");
  }
}
drawScanpath(pg);
drawFixations(pg);
drawBlinks(pg);
drawOverlay(pg);

  pg.endDraw();

  String outDir = outputDirFor(SEGMENT_CSV) + "/" + EXPORT_SUBDIR;
  ensureDir(outDir);

  String outName = safeFilename(baseName(SEGMENT_CSV)) + ".png";
  pg.save(outDir + "/" + outName);

  println("FERTIG: " + outDir + "/" + outName);
  exit();
}

void parseFilenameMeta(String path) {
  String bn = baseName(path);
  if (bn.startsWith("1er."))   cond = 1;
  if (bn.startsWith("4er."))   cond = 4;
  if (bn.startsWith("20er."))  cond = 20;
  if (bn.startsWith("100er.")) cond = 100;

  isZoom = bn.toLowerCase().contains("zoom");
  setFromNameIdx = parseIntAfter(bn, "Set");
  zoomFromNameIdx = parseIntAfter(bn, "Bild");
}

int parseIntAfter(String s, String token) {
  int p = s.indexOf(token);
  if (p < 0) return -1;
  p += token.length();
  String num = "";
  while (p < s.length()) {
    char c = s.charAt(p);
    if (c >= '0' && c <= '9') { num += c; p++; }
    else break;
  }
  if (num.length() == 0) return -1;
  try { return Integer.parseInt(num); } catch(Exception e){ return -1; }
}

String baseName(String path) {
  path = path.replace("\\", "/");
  int i = path.lastIndexOf("/");
  String bn = (i>=0) ? path.substring(i+1) : path;
  if (bn.toLowerCase().endsWith(".csv")) bn = bn.substring(0, bn.length()-4);
  return bn;
}

String outputDirFor(String path) {
  path = path.replace("\\", "/");
  int i = path.lastIndexOf("/");
  return (i>=0) ? path.substring(0, i) : ".";
}

void loadSegmentCsv(String path) {
  String[] lines = loadStrings(path);
  if (lines == null || lines.length < 2) { exit(); }

  int idx = 0;
  while (idx < lines.length && trim(lines[idx]).length() == 0) idx++;
  if (idx >= lines.length) { exit(); }

  int firstMs = -1;

  for (int i = idx+1; i < lines.length; i++) {
    String ln = trim(lines[i]);
    if (ln.length() == 0) continue;
    String[] c = split(ln, SEP);
    if (c.length < 6) continue;

    int ms;
    try { ms = Integer.parseInt(c[0]); } catch(Exception e){ continue; }
    if (firstMs < 0) firstMs = ms;
    int t = ms - firstMs;

    Row r = new Row();
    r.t = t;
    r.event = c[2];
    r.payload = c[3];
    r.gx = parseFloatSafe(c[4]);
    r.gy = parseFloatSafe(c[5]);
    rows.add(r);

    if (r.event.equals("GAZE")) {
      GazeSample g = new GazeSample();
      g.t = t; g.gx = r.gx; g.gy = r.gy;
      gaze.add(g);
    }

    totalT = max(totalT, t);
  }
}

float parseFloatSafe(String s) {
  try { return Float.parseFloat(s); } catch(Exception e){ return Float.NaN; }
}

void extractStimulusInfoFromPayload() {
  for (Row r : rows) {
    if (r.payload == null) continue;
    HashMap<String,String> m = parsePayload(r.payload);

    if (animalFolder == null && m.containsKey("animal_name")) {
      String a = trim(m.get("animal_name"));
      if (a.length() > 0) animalFolder = a;
    }

    if (!isZoom) {
      if (ids == null && m.containsKey("ids")) {
        ids = split(m.get("ids"), '|');
      }
    } else {
      if (zoomId == null && m.containsKey("image_id")) zoomId = m.get("image_id");
      if (zoomId == null && m.containsKey("selected_id")) zoomId = m.get("selected_id");
    }
  }
  
  // FALLBACK: ids aus Teilnehmer+LatinSquare rekonstruieren
  if (!isZoom && (ids == null || ids.length == 0)) {
    int pNo = participantNoFromPath(SEGMENT_CSV);
    if (pNo >= 0 && setFromNameIdx > 0 && cond > 0) {
      ids = idsForSetFromParticipant(pNo, cond, setFromNameIdx);

      // optional: folder direkt auch setzen (damit overlay stimmt)
      animalFolder = animalForCondFromParticipant(pNo, cond).toLowerCase();
    }
  }

  // Zoom-Fallback (wenn zoomId fehlt): aus Set+Bildindex ableiten
  if (isZoom && (zoomId == null || zoomId.trim().length()==0)) {
    int pNo = participantNoFromPath(SEGMENT_CSV);
    if (pNo >= 0 && setFromNameIdx > 0 && zoomFromNameIdx > 0 && cond > 0) {
      String[] setIds = idsForSetFromParticipant(pNo, cond, setFromNameIdx);
      int idx = zoomFromNameIdx - 1; // 1-basiert -> 0-basiert
      if (idx >= 0 && idx < setIds.length) zoomId = setIds[idx];
      animalFolder = animalForCondFromParticipant(pNo, cond).toLowerCase();
    }
  }
}

HashMap<String,String> parsePayload(String payload) {
  HashMap<String,String> map = new HashMap<String,String>();
  if (payload == null) return map;
  String[] parts = splitTokens(payload, ",;");
  for (String p : parts) {
    p = trim(p);
    int eq = p.indexOf('=');
    if (eq > 0 && eq < p.length()-1) {
      String k = trim(p.substring(0, eq));
      String v = trim(p.substring(eq+1));
      map.put(k, v);
    }
  }
  return map;
}

void detectGazeCoordinateMode() {
  ArrayList<Float> xs = new ArrayList<Float>();
  ArrayList<Float> ys = new ArrayList<Float>();
  for (GazeSample g : gaze) {
    if (Float.isNaN(g.gx) || Float.isNaN(g.gy)) continue;
    xs.add(g.gx); ys.add(g.gy);
  }
  if (xs.isEmpty()) {
    gazeIsNormalized = true;
    gazeBaseW = 1; gazeBaseH = 1;
    return;
  }

  float p99x = percentile(xs, 0.99f);
  float p99y = percentile(ys, 0.99f);

  if (p99x <= 1.2f && p99y <= 1.2f) {
    gazeIsNormalized = true;
    gazeBaseW = 1; gazeBaseH = 1;
  } else {
    gazeIsNormalized = false;
    gazeBaseW = max(1, p99x);
    gazeBaseH = max(1, p99y);
  }
}

float percentile(ArrayList<Float> arr, float p) {
  ArrayList<Float> a = new ArrayList<Float>(arr);
  Collections.sort(a);
  int n = a.size();
  float fp = p * (n - 1);
  int idx = (int)floor(fp);
  idx = constrain(idx, 0, n-1);
  return a.get(idx);
}

float gazeToX(GazeSample g) {
  if (gazeIsNormalized) return g.gx * EXPORT_W;
  return (g.gx / gazeBaseW) * EXPORT_W;
}
float gazeToY(GazeSample g) {
  if (gazeIsNormalized) return g.gy * EXPORT_H;
  return (g.gy / gazeBaseH) * EXPORT_H;
}

void computeBlinks() {
  blinks.clear();
  for (int i = 1; i < gaze.size(); i++) {
    int dt = gaze.get(i).t - gaze.get(i-1).t;
    if (dt >= blinkThr) {
      Blink b = new Blink();
      b.startT = gaze.get(i-1).t;
      b.endT   = gaze.get(i).t;
      blinks.add(b);
    }
  }
}

void computeFixations() {
  fixations.clear();
  Fixation cur = null;

  for (int i=0;i<gaze.size();i++){
    GazeSample g = gaze.get(i);
    if (Float.isNaN(g.gx) || Float.isNaN(g.gy)) continue;

    if (i>0) {
      int dt = g.t - gaze.get(i-1).t;
      if (dt > blinkThr) {
        if (cur != null && cur.dur() >= FIX_MIN_MS) fixations.add(cur);
        cur = null;
      }
    }

    float x = gazeToX(g);
    float y = gazeToY(g);

    if (cur == null) {
      cur = new Fixation();
      cur.x=x; cur.y=y; cur.startT=g.t; cur.endT=g.t;
    } else {
      float dx = x-cur.x, dy=y-cur.y;
      float dist = sqrt(dx*dx+dy*dy);
      if (dist <= FIX_MAX_DIST_PX) {
        cur.x = (cur.x + x)*0.5;
        cur.y = (cur.y + y)*0.5;
        cur.endT = g.t;
      } else {
        if (cur.dur() >= FIX_MIN_MS) fixations.add(cur);
        cur = new Fixation();
        cur.x=x; cur.y=y; cur.startT=g.t; cur.endT=g.t;
      }
    }
  }
  if (cur != null && cur.dur() >= FIX_MIN_MS) fixations.add(cur);
}

String folderForCond() {
  String f = null;

  if (animalFolder != null && animalFolder.trim().length() > 0) f = animalFolder.trim();
  else if (cond == 1)   f = "Katze";
  else if (cond == 4)   f = "Hund";
  else if (cond == 20)  f = "Pferd";
  else if (cond == 100) f = "Hase";
  else                  f = "Katze";

  return f.toLowerCase();
}

PImage loadImageSmart(String pathMaybeNoExt) {
  PImage img = loadImage(pathMaybeNoExt);
  if (img != null) return img;
  String low = pathMaybeNoExt.toLowerCase();
  boolean hasExt = low.endsWith(".jpg")||low.endsWith(".jpeg")||low.endsWith(".png");
  if (!hasExt) {
    img = loadImage(pathMaybeNoExt + ".png");  if (img!=null) return img;
    img = loadImage(pathMaybeNoExt + ".jpg");  if (img!=null) return img;
    img = loadImage(pathMaybeNoExt + ".jpeg"); if (img!=null) return img;
  }
  return null;
}

void drawSetBackground(PGraphics pg) {
  String folder = folderForCond();

  if (ids == null || ids.length == 0) {
    pg.fill(220);
    pg.textAlign(CENTER, CENTER);
    pg.text("WARN: ids=... nicht in CSV gefunden.", EXPORT_W/2, EXPORT_H/2);
    return;
  }

  if (cond == 1) {
    PImage img = loadImageSmart(IMG_DIR + "/" + folder + "/" + ids[0]);
    drawSingleImage(pg, img);
  } else if (cond == 4) {
    drawGrid(pg, folder, ids, 2, 2);
  } else if (cond == 20) {
    drawGrid(pg, folder, ids, 5, 4);
  } else if (cond == 100) {
    drawGrid100(pg, folder, ids);
  } else {
    drawGrid(pg, folder, ids, 2, 2);
  }
}

void drawZoomBackground(PGraphics pg) {
  String folder = folderForCond();

  if (zoomId != null && trim(zoomId).length() > 0) {
    PImage img = loadImageSmart(IMG_DIR + "/" + folder + "/" + zoomId);
    drawZoomImage(pg, img);
    return;
  }

  if (ids != null && zoomFromNameIdx > 0 && zoomFromNameIdx <= ids.length) {
    String id = ids[zoomFromNameIdx-1];
    PImage img = loadImageSmart(IMG_DIR + "/" + folder + "/" + id);
    drawZoomImage(pg, img);
    return;
  }

  pg.fill(220);
  pg.textAlign(CENTER, CENTER);
  pg.text("WARN: zoomId nicht in CSV gefunden.", EXPORT_W/2, EXPORT_H/2);
}

void drawSingleImage(PGraphics pg, PImage img) {
  if (img == null) {
    pg.fill(220);
    pg.textAlign(CENTER,CENTER);
    pg.text("Bild fehlt", EXPORT_W/2, EXPORT_H/2);
    return;
  }
  int top = 80;
  int areaH = int(EXPORT_H * 0.78);
  float maxW = EXPORT_W * 0.70;
  float maxH = areaH;
  float sc = min(maxW / img.width, maxH / img.height);
  pg.image(img, EXPORT_W/2, top + areaH/2, int(img.width*sc), int(img.height*sc));
}

void drawZoomImage(PGraphics pg, PImage img) {
  pg.fill(0, 180);
  pg.noStroke();
  pg.rect(0, 0, EXPORT_W, EXPORT_H);

  // Bild wie im Original (0.8 * screen), nicht aspect-fit
  if (img != null) {
    pg.imageMode(CENTER);
    float mw = EXPORT_W * 0.8;
    float mh = EXPORT_H * 0.8;
    pg.image(img, EXPORT_W/2, EXPORT_H/2, mw, mh);
  } else {
    pg.fill(240);
    pg.textAlign(CENTER, CENTER);
    pg.text("Zoom-Bild fehlt", EXPORT_W/2, EXPORT_H/2);
  }

  pg.fill(240);
  pg.textAlign(LEFT, TOP);
  pg.text("ID: " + (zoomId != null ? zoomId : ""), 40, 40);

  drawFakeButton(pg, EXPORT_W/2 - 100, EXPORT_H - 90, 200, 56, "Auswählen");
  drawFakeButton(pg, 40, 40, 160, 44, "Schließen");
}

void drawFakeButton(PGraphics pg, int x, int y, int w, int h, String label, boolean disabled) {
  pg.noStroke();
  if (disabled) pg.fill(90, 90, 90);
  else          pg.fill(60, 160, 90);
  pg.rect(x, y, w, h, 8);

  pg.fill(255);
  pg.textAlign(CENTER, CENTER);
  pg.text(label, x + w/2, y + h/2);
  pg.textAlign(LEFT, BASELINE);
}

void drawFakeButton(PGraphics pg, int x, int y, int w, int h, String label) {
  drawFakeButton(pg, x, y, w, h, label, false);
}

void drawFakeNavBar(PGraphics pg) {
  int y = EXPORT_H - 90;

  if (cond == 100) return;

  boolean leftDisabled  = (setFromNameIdx <= 1);
  boolean rightDisabled = false;

  drawFakeButton(pg, 40, y, 140, 44, "← Zurück", leftDisabled);

  int rightX = EXPORT_W - 240;
  drawFakeButton(pg, rightX, y, 180, 44, "→ Weiter", rightDisabled);
}

void drawFakeTitle(PGraphics pg) {
  pg.fill(240);
  pg.textAlign(CENTER, TOP);
  pg.textFont(font28);
  pg.text("Bedingung: " + cond + " Bild(e)", EXPORT_W/2, 30);

  pg.textAlign(LEFT, BASELINE);
  pg.textFont(font18);
}

int participantNoFromPath(String path){
  String p = path.replace("\\","/");
  int i = p.toLowerCase().indexOf("teilnehmer");
  if (i < 0) return -1;
  i += "teilnehmer".length();
  String num = "";
  while (i < p.length()){
    char c = p.charAt(i);
    if (c>='0' && c<='9'){ num += c; i++; }
    else break;
  }
  if (num.length()==0) return -1;
  return int(num);
}

int[] latinRow(int pNo){
  int[][] latin = {
    {1,4,20,100},
    {4,20,100,1},
    {20,100,1,4},
    {100,1,4,20}
  };
  return latin[pNo % 4];
}

String animalForCondFromParticipant(int pNo, int cond){
  String[] ANIMALS = { "Katze", "Hund", "Pferd", "Hase" };

  int[] order = latinRow(pNo);
  int block = pNo / 4;

  // animalOrder[pos] = (pos + block) % 4
  for (int pos=0; pos<4; pos++){
    if (order[pos] == cond){
      int aIdx = (pos + block) % ANIMALS.length;
      return ANIMALS[aIdx];
    }
  }
  return ANIMALS[0];
}

String[] listSortedImagesInFolder(String folderLower){
  File dir = new File(IMG_DIR + "/" + folderLower);
  File[] files = dir.listFiles();
  if (files == null) return new String[0];

  Arrays.sort(files);
  ArrayList<String> out = new ArrayList<String>();
  for (int i=0; i<files.length && out.size()<100; i++){
    if (!files[i].isFile()) continue;
    String name = files[i].getName().toLowerCase();
    if (!name.matches(".*\\.(png|jpg|jpeg)$")) continue;
    out.add(files[i].getName()); // original case
  }
  return out.toArray(new String[0]);
}

String[] idsForSetFromParticipant(int pNo, int cond, int setIdx1Based){
  String animal = animalForCondFromParticipant(pNo, cond);
  String folderLower = animal.toLowerCase();

  String[] all = listSortedImagesInFolder(folderLower);
  int start = (setIdx1Based - 1) * cond;
  if (start < 0 || start >= all.length) return new String[0];

  int n = min(cond, all.length - start);
  String[] ids = new String[n];
  for (int i=0;i<n;i++) ids[i] = all[start+i];
  return ids;
}

void drawGrid(PGraphics pg, String folder, String[] ids, int cols, int rows) {
  int margin = 20;
  int top = 90;

  int gridW = EXPORT_W - margin*2;
  int gridH = EXPORT_H - top - margin - 120;

  int cellW = gridW / cols;
  int cellH = gridH / rows;

  int maxN = min(ids.length, cols*rows);

  for (int i = 0; i < maxN; i++) {
    int c = i % cols;
    int r = i / cols;

    int xRect = margin + c * cellW + 10;
    int yRect = top    + r * cellH + 10;
    int wRect = cellW - 20;
    int hRect = cellH - 20;

    pg.noFill();
    pg.stroke(80);
    pg.rect(xRect, yRect, wRect, hRect, 10);

    PImage img = loadImageSmart(IMG_DIR + "/" + folder + "/" + ids[i]);
    if (img != null) {
      float sc = min((float)wRect / img.width, (float)hRect / img.height);
      pg.image(img, xRect + wRect/2, yRect + hRect/2, int(img.width*sc), int(img.height*sc));
    }
  }
}

void drawGrid100(PGraphics pg, String folder, String[] ids) {
  int cols = 10, rows = 10;
  int top = 90;
  int bottomMargin = 50;
  int maxGridH = EXPORT_H - top - bottomMargin;

  float widthFactor = 0.85f;
  int targetGridW = int(EXPORT_W * widthFactor);
  float targetAspect = 16.0f / 9.0f;

  int cellW = targetGridW / cols;
  int cellH = int(cellW / targetAspect);
  int gridH = cellH * rows;

  if (gridH > maxGridH){
    float sc = (float)maxGridH / (float)gridH;
    cellW = int(cellW * sc);
    cellH = int(cellH * sc);
    gridH = cellH * rows;
  }

  int gridW = cellW * cols;
  int startX = (EXPORT_W - gridW) / 2;
  int innerPad = 4;

  int maxN = min(ids.length, cols*rows);

  for (int i = 0; i < maxN; i++) {
    int c = i % cols;
    int r = i / cols;

    int xRect = startX + c * cellW + innerPad/2;
    int yRect = top    + r * cellH + innerPad/2;
    int wRect = cellW - innerPad;
    int hRect = cellH - innerPad;

    pg.noFill();
    pg.stroke(80);
    pg.rect(xRect, yRect, wRect, hRect, 10);

    PImage img = loadImageSmart(IMG_DIR + "/" + folder + "/" + ids[i]);
    if (img != null) {
      float sc = min((float)wRect / img.width, (float)hRect / img.height);
      pg.image(img, xRect + wRect/2, yRect + hRect/2, int(img.width*sc), int(img.height*sc));
    }
  }
}

void drawScanpath(PGraphics pg) {
  if (gaze.size() < 2) return;

  pg.strokeWeight(2);

  GazeSample prev = null;

  for (int i = 0; i < gaze.size(); i++) {
    GazeSample g = gaze.get(i);
    if (Float.isNaN(g.gx) || Float.isNaN(g.gy)) { prev = null; continue; }

    if (prev != null) {
      int dt = g.t - prev.t;

      float x1 = gazeToX(prev), y1 = gazeToY(prev);
      float x2 = gazeToX(g),    y2 = gazeToY(g);

      boolean isBlinkJump = (dt > blinkThr);

      if (isBlinkJump) {
        if (SHOW_BLINKS) {
          pg.stroke(255, 80, 80, 200);
          drawSegmentClippedByFixations(pg, x1, y1, x2, y2);
        }
      } else {
        pg.stroke(0, 255, 0, 160);
        drawSegmentClippedByFixations(pg, x1, y1, x2, y2);
      }
    }

    prev = g;
  }
}

boolean pointInsideAnyFixation(float x, float y) {
  for (Fixation f : fixations) {
    int dur = f.dur();
    if (dur < FIX_MIN_MS) continue;

    float r = map(dur, FIX_MIN_MS, 800, 8, 40);
    r = constrain(r, 6, 45);

    float dx = x - f.x;
    float dy = y - f.y;

    if (dx*dx + dy*dy <= r*r) {
      return true;
    }
  }
  return false;
}

void drawSegmentClippedByFixations(PGraphics pg, float x1, float y1, float x2, float y2) {
  if (!HIDE_SCANPATH_INSIDE_FIXATIONS) {
    pg.line(x1, y1, x2, y2);
    return;
  }

  float dx = x2 - x1;
  float dy = y2 - y1;
  float dist = sqrt(dx*dx + dy*dy);
  int steps = max(2, (int)(dist / 6.0f));

  float px = x1, py = y1;
  boolean pOut = !pointInsideAnyFixation(px, py);

  for (int s = 1; s <= steps; s++) {
    float a = (float)s / (float)steps;
    float cx = x1 + dx * a;
    float cy = y1 + dy * a;

    boolean cOut = !pointInsideAnyFixation(cx, cy);

    if (pOut && cOut) {
      pg.line(px, py, cx, cy);
    }

    px = cx; py = cy;
    pOut = cOut;
  }
}

void drawFixations(PGraphics pg) {
  for (Fixation f : fixations) {
    int dur = f.dur();
    if (dur < FIX_MIN_MS) continue;

    float r = map(dur, FIX_MIN_MS, 800, 8, 40);
    r = constrain(r, 6, 45);

    pg.noFill();
    pg.stroke(0,180,255,255);
    pg.strokeWeight(4);
    pg.ellipse(f.x, f.y, r*2, r*2);
  }
}

void drawBlinks(PGraphics pg) {
   if (!SHOW_BLINKS) return;
  int y = EXPORT_H - 30;
  int left = 60;
  int right = EXPORT_W - 60;
  int segDur = max(1, totalT);

  pg.stroke(180);
  pg.strokeWeight(2);
  pg.line(left, y, right, y);

  pg.stroke(255,80,80);
  pg.strokeWeight(8);

  for (Blink b : blinks) {
    float x1 = map(b.startT, 0, segDur, left, right);
    float x2 = map(b.endT,   0, segDur, left, right);
    pg.line(x1, y, x2, y);
  }
}

void drawOverlay(PGraphics pg) {
  pg.fill(255);
  pg.textAlign(LEFT, TOP);
  pg.textFont(font18);

  String bn = baseName(SEGMENT_CSV);
  String mode = gazeIsNormalized ? "norm(0..1)" : "pixel->scaled";

  pg.text("File: " + bn, 20, 16);
  pg.text("cond=" + cond + " | folder=" + folderForCond() + " | zoom=" + isZoom + " | setIdx=" + setFromNameIdx + " | zoomIdx=" + zoomFromNameIdx, 20, 40);
  pg.text("t=0–" + totalT + " ms | gaze=" + gaze.size() + " | fix=" + fixations.size() + " | blinks=" + blinks.size()
         + "ms | thr=" + blinkThr + "ms | gazeMode=" + mode, 20, 64);

  pg.textAlign(CENTER, TOP);
  pg.textFont(font28);
  pg.text((isZoom ? "ZOOM" : "SET") + " – Modus " + cond, EXPORT_W/2, 12);

  pg.textAlign(LEFT, BASELINE);
  pg.textFont(font18);
}

void ensureDir(String path) {
  File f = new File(path);
  if (!f.exists()) f.mkdirs();
}

String safeFilename(String s) {
  if (s == null) return "null";
  String t = s;
  t = t.replace("/", "_").replace("\\", "_").replace(":", "_").replace("*", "_");
  t = t.replace("?", "_").replace("\"", "_").replace("<", "_").replace(">", "_").replace("|", "_");
  return t;
}
