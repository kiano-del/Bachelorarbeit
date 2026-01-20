import java.util.*;
import java.io.*;

final String BASE_DIR = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/UmfrageErgebnisse";
final String IMG_DIR  = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/Umfragebogen/bilder_sets";

final String PARTICIPANT = "Teilnehmer0";
final String RAW_FILE    = "raw.csv";

final char SEP = ';';

HashMap<Integer,String> condFolderHint = new HashMap<Integer,String>();

final int WELCOME=0, CONSENT=1, DEMO=2, TASKINFO=7, CALIB=8, TASK=3, POST_TRIAL=4, FINAL_SURVEY=5, THANKS=6;

final int[] CONDS = {1,4,20,100};
final String[] ANIMALS = {"Katze","Hund","Pferd","Hase"};

int participantNo = -1;
int[] condOrder = new int[4];
int[] animalOrder = new int[4];
int orderPos = 0;
boolean orderInited = false;

class LogRow {
  int t;
  int state;
  String event;
  String payload;
  float gx, gy;
}

class GazeSample {
  int t;
  float gx, gy;
}

ArrayList<LogRow> logRows = new ArrayList<LogRow>();
ArrayList<GazeSample> gaze = new ArrayList<GazeSample>();

int totalDuration = 0;
float replayT = 0;
float speed = 1.0;
float trailMs = 3000;
int lastFrameMs = 0;
int nextLogIdx = 0;
boolean paused = false;

int currentState = WELCOME;

int currentCond = -1;
int currentSet = -1;
String[] currentIds = new String[0];
PImage[] currentImgs = new PImage[0];

boolean zoomOpen = false;
int zoomCond = -1;
String zoomId = "";
PImage zoomImg = null;

int postRating = -1;
int postCond = -1;
String postSelectedId = "";
PImage postSelectedImg = null;

int finalFavCond = -1;

int demoGenderIdx = -1;
String demoAge = "";
HashMap<String,String> demoExtra = new HashMap<String,String>();

HashMap<Integer,String> condAnimalName = new HashMap<Integer,String>();

HashSet<String> doneCalibPoints = new HashSet<String>();

HashMap<String, PImage> replayCache = new HashMap<String, PImage>();
ArrayList<String> preloadKeys = new ArrayList<String>();
HashSet<String> preloadKeySet = new HashSet<String>();
boolean replayLoading = true;
int preloadIndex = 0;

void settings() {
  fullScreen();
}

void setup() {
  surface.setTitle("Replay – komplette Session");
  textFont(createFont("Arial", 18));
  background(20);

  String path = BASE_DIR + "/" + PARTICIPANT + "/" + RAW_FILE;
  loadRaw(path);

  buildCondAnimalNameFromLogs();

  participantNo = parseParticipantNoFromName(PARTICIPANT);
  if (participantNo < 0) participantNo = 0;
  initOrderFromParticipantNo(participantNo);

  prepareReplayPreload();

  lastFrameMs = millis();
}

void draw() {
  int now = millis();
  int dt = now - lastFrameMs;
  lastFrameMs = now;

  if (replayLoading) {
    background(20);
    drawReplayLoadingScreen();
    preloadStepOne();
    return;
  }

  if (!paused) {
    replayT += dt * speed;
    if (replayT > totalDuration) replayT = totalDuration;

    while (nextLogIdx < logRows.size() && logRows.get(nextLogIdx).t <= replayT) {
      processRow(logRows.get(nextLogIdx));
      nextLogIdx++;
    }
  }

  background(20);

  switch (currentState) {
    case WELCOME:      drawWelcomeReplay();      break;
    case CONSENT:      drawConsentReplay();      break;
    case DEMO:         drawDemoReplay();         break;
    case TASKINFO:     drawTaskInfoReplay();     break;
    case CALIB:        drawCalibReplay();        break;
    case TASK:         drawTaskReplay();         break;
    case POST_TRIAL:   drawPostTrialReplay();    break;
    case FINAL_SURVEY: drawFinalSurveyReplay();  break;
    case THANKS:       drawThanksReplay();       break;
    default:           drawUnknownReplay();      break;
  }

  drawGazeTrail();
  drawOverlay();
}

void prepareReplayPreload() {
  replayCache.clear();
  preloadKeys.clear();
  preloadKeySet.clear();
  preloadIndex = 0;

  collectNeededImagesFromLogs();

  replayLoading = true;
}

void drawReplayLoadingScreen() {
  fill(240);
  textAlign(CENTER, CENTER);
  textSize(32);
  text("Replay wird geladen…", width/2, height/2 - 30);

  textSize(18);
  int total = preloadKeys.size();
  text(preloadIndex + " / " + total, width/2, height/2 + 10);

  int barW = int(width * 0.5);
  int barH = 14;
  int bx = width/2 - barW/2;
  int by = height/2 + 40;
  noFill();
  stroke(180);
  rect(bx, by, barW, barH, 6);

  float p = (total == 0) ? 1 : (float)preloadIndex / (float)total;
  noStroke();
  fill(80, 200, 255);
  rect(bx, by, int(barW * p), barH, 6);

  textAlign(LEFT, BASELINE);
  textSize(18);
}

String removeExt(String s){
  if (s == null) return "";
  int dot = s.lastIndexOf('.');
  if (dot > 0) return s.substring(0, dot);
  return s;
}

String resolveIdForCond(int cond, String id){
  if (id == null) return null;
  id = cleanId(id);
  if (id == null) return null;
  if (id.length() == 0) return id;

  String f1 = folderForCond(cond);
  File a0 = new File(IMG_DIR + "/" + f1 + "/" + id);
  if (a0.exists()) return id;

  String f2 = folderFromId(id);
  if (f2 != null && folderExists(f2)) {
    File b0 = new File(IMG_DIR + "/" + f2 + "/" + id);
    if (b0.exists()) return id;
  }

  String base = removeExt(id);
  String[] exts = {".png",".jpg",".jpeg",".PNG",".JPG",".JPEG"};

  for (String e : exts){
    String cand = base + e;
    File a = new File(IMG_DIR + "/" + f1 + "/" + cand);
    if (a.exists()) return cand;

    if (f2 != null && folderExists(f2)) {
      File b = new File(IMG_DIR + "/" + f2 + "/" + cand);
      if (b.exists()) return cand;
    }
  }

  return id;
}

int parseParticipantNoFromName(String p){
  if (p == null) return -1;
  String digits = "";
  for (int i=0;i<p.length();i++){
    char ch = p.charAt(i);
    if (ch >= '0' && ch <= '9') digits += ch;
  }
  if (digits.length() == 0) return -1;
  try { return Integer.parseInt(digits); } catch(Exception e){ return -1; }
}

void initOrderFromParticipantNo(int pNo){
  int[][] latin = {
    {1,4,20,100},
    {4,20,100,1},
    {20,100,1,4},
    {100,1,4,20}
  };
  int idx = ((pNo % 4) + 4) % 4;
  for (int i=0;i<4;i++) condOrder[i] = latin[idx][i];

  int block = (pNo / 4);
  for (int pos=0; pos<4; pos++){
    animalOrder[pos] = (pos + block) % ANIMALS.length;
  }

  orderPos = 0;
  orderInited = true;
}

String animalNameForPos(int pos){
  if (pos < 0 || pos >= 4) return "";
  return ANIMALS[ animalOrder[pos] ];
}

void beginConditionAtPos(int pos){
  if (!orderInited) return;
  if (pos < 0 || pos >= 4) return;

  currentCond = condOrder[pos];
  currentSet  = 0;

  String animal = animalNameForPos(pos);
  if (animal != null && animal.trim().length() > 0){
    condAnimalName.put(currentCond, animal);
  }

  currentIds = idsForCondSet(currentCond, currentSet);
  loadCurrentImages();
}

boolean hasNextCondition(){
  return orderInited && (orderPos + 1) < 4;
}

void advanceToNextCondition(){
  if (!orderInited) return;
  orderPos++;
  if (orderPos < 4){
    beginConditionAtPos(orderPos);
  } else {
    currentState = FINAL_SURVEY;
  }
}

int nextStateByBtnNext(int st){
  if (st == WELCOME) return CONSENT;
  if (st == CONSENT) return DEMO;
  if (st == DEMO) return TASKINFO;
  if (st == TASKINFO) return CALIB;

  if (st == CALIB) {
    orderPos = 0;
    beginConditionAtPos(orderPos);
    return TASK;
  }

if (st == POST_TRIAL) return TASK;

  if (st == FINAL_SURVEY) return THANKS;
  return st;
}

void preloadStepOne() {
  if (preloadIndex >= preloadKeys.size()) {
    replayLoading = false;
    replayT = 0;
    nextLogIdx = 0;
    currentState = WELCOME;
    paused = false;
    return;
  }

  String key0 = preloadKeys.get(preloadIndex);
  int sep = key0.indexOf('|');
  int cond = -1;
  String id = key0;

  if (sep >= 0) {
    try { cond = Integer.parseInt(key0.substring(0, sep)); } catch(Exception e) {}
    id = key0.substring(sep + 1);
  }

  String idResolved = resolveIdForCond(cond, id);
  String cacheKey = cond + "|" + idResolved;

  if (!replayCache.containsKey(cacheKey)) {
    String folder = folderFromId(idResolved);
    if (folder == null || !folderExists(folder)) folder = folderForCond(cond);

    String path = IMG_DIR + "/" + folder + "/" + idResolved;
    PImage img = loadImage(path);

    replayCache.put(cacheKey, img);
  }

  preloadIndex++;
}

PImage getCached(int cond, String id) {
  if (id == null) return null;
  id = resolveIdForCond(cond, id);
  String key = cond + "|" + id;
  return replayCache.get(key);
}

void addPreloadKey(int cond, String id) {
  if (cond <= 0) return;
  if (id == null) return;
  id = trim(id);
  if (id.length() == 0) return;

  id = resolveIdForCond(cond, id);

  String key = cond + "|" + id;
  if (!preloadKeySet.contains(key)) {
    preloadKeySet.add(key);
    preloadKeys.add(key);
  }
}

String animalFolderFromFolderForCond(String folderForCondOut) {
  if (folderForCondOut == null) return "";
  String f = folderForCondOut.trim().toLowerCase();
  return f;
}

String[] listAnimalImagesSorted(String folder) {
  folder = animalFolderFromFolderForCond(folder);
  File dir = new File(IMG_DIR + "/" + folder);
  if (!dir.exists() || !dir.isDirectory()) return new String[0];

  String[] files = dir.list();
  if (files == null) return new String[0];

  ArrayList<String> imgs = new ArrayList<String>();
  for (String f : files) {
    if (f == null) continue;
    String fl = f.toLowerCase();
    if (fl.endsWith(".png") || fl.endsWith(".jpg") || fl.endsWith(".jpeg")) {
      imgs.add(f);
    }
  }
  Collections.sort(imgs, String.CASE_INSENSITIVE_ORDER);
  return imgs.toArray(new String[0]);
}

String[] idsForCondSet(int cond, int setIdx){
  if (cond <= 0 || setIdx < 0) return new String[0];

  String folder = folderForCond(cond);
  String[] all = listAnimalImagesSorted(folder);
  if (all.length == 0) return new String[0];

  int start;
  if (setIdx >= 1) start = (setIdx - 1) * cond;
  else            start = setIdx * cond;

  int end = min(start + cond, all.length);
  if (start < 0 || start >= all.length) return new String[0];

  String[] ids = new String[end - start];
  for (int i = start; i < end; i++) ids[i - start] = all[i];
  return ids;
}

void addWholeSetToPreload(int cond, int setIdx) {
  String[] ids = idsForCondSet(cond, setIdx);
  for (String id : ids) addPreloadKey(cond, id);
}

void collectNeededImagesFromLogs() {
  int lastCondSeen = -1;
  HashMap<Integer,Integer> maxSetByCond = new HashMap<Integer,Integer>();

  for (int i = 0; i < logRows.size(); i++) {
    LogRow r = logRows.get(i);
    String ev = r.event;
    HashMap<String,String> m = parsePayload(r.payload);

    if (m.containsKey("cond")) {
      try { lastCondSeen = Integer.parseInt(m.get("cond")); } catch(Exception e) {}
    }

    if (ev.equals("EVENT_SHOW_SET") || ev.equals("NAV_FWD") || ev.equals("NAV_BACK")) {
      int c = lastCondSeen;
      if (m.containsKey("cond")) { try { c = Integer.parseInt(m.get("cond")); } catch(Exception e) {} }

      int s = -1;
      if (m.containsKey("set")) {
        try { s = Integer.parseInt(m.get("set")); } catch(Exception e) {}
      }

      if (s >= 0) {
        Integer prev = maxSetByCond.get(c);
        if (prev == null || s > prev) maxSetByCond.put(c, s);
        addWholeSetToPreload(c, s);
      }

      if (m.containsKey("ids")) {
        String[] ids = split(m.get("ids"), '|');
        for (String id : ids) addPreloadKey(c, id);
      }
    }

    if (ev.equals("EVENT_ZOOM_OPEN") || ev.equals("EVENT_SELECT") || ev.equals("EVENT_POST_TRIAL")) {
      int c = lastCondSeen;
      if (m.containsKey("cond")) { try { c = Integer.parseInt(m.get("cond")); } catch(Exception e) {} }

      int s = -1;
      if (m.containsKey("set")) {
        try { s = Integer.parseInt(m.get("set")); } catch(Exception e) {}
      } else {
        s = inferSetFromImageIdx(c, m);
      }

      if (s >= 0) {
        Integer prev = maxSetByCond.get(c);
        if (prev == null || s > prev) maxSetByCond.put(c, s);
        addWholeSetToPreload(c, s);
      }

      if (m.containsKey("image_id")) addPreloadKey(c, m.get("image_id"));
      if (m.containsKey("selected_id")) addPreloadKey(c, m.get("selected_id"));
    }
  }

  for (Integer cObj : maxSetByCond.keySet()) {
    int c = cObj;
    int maxS = maxSetByCond.get(cObj);
    for (int s = 0; s <= maxS; s++) addWholeSetToPreload(c, s);
  }
}

String cleanId(String s){
  if (s == null) return null;
  s = trim(s);
  if (s.length() == 0) return s;

  if (s.startsWith("\"") && s.endsWith("\"") && s.length() >= 2) s = s.substring(1, s.length()-1);
  if (s.startsWith("'")  && s.endsWith("'")  && s.length() >= 2) s = s.substring(1, s.length()-1);

  while (s.startsWith("[") || s.startsWith("(") || s.startsWith("{")) s = s.substring(1).trim();
  while (s.endsWith("]")   || s.endsWith(")")   || s.endsWith("}"))   s = s.substring(0, s.length()-1).trim();

  return s;
}

int inferSetFromImageIdx(int cond, HashMap<String,String> m) {
  if (cond <= 0 || m == null) return -1;
  if (!m.containsKey("image_idx")) return -1;
  try {
    int idx = Integer.parseInt(m.get("image_idx"));
    return idx / cond;
  } catch(Exception e) {
    return -1;
  }
}

void buildCondAnimalNameFromLogs() {
  for (LogRow r : logRows) {
    HashMap<String,String> m = parsePayload(r.payload);
    if (m.containsKey("cond") && m.containsKey("animal_name")) {
      try {
        int c = Integer.parseInt(m.get("cond"));
        String animal = m.get("animal_name");
        if (animal != null && trim(animal).length() > 0) {
          condAnimalName.put(c, animal);
        }
      } catch(Exception e){}
    }
  }
}

void loadRaw(String path) {
  String[] lines = loadStrings(path);
  if (lines == null || lines.length < 2) return;

  int idx = 0;
  while (idx < lines.length && trim(lines[idx]).length() == 0) idx++;
  if (idx >= lines.length) return;

  String headerLine = trim(lines[idx]);
  String[] header = split(headerLine, SEP);

  int firstMs = -1;
  int lastMs  = 0;

  for (int i = idx+1; i < lines.length; i++) {
    String ln = trim(lines[i]);
    if (ln.length() == 0) continue;

    String[] cols = split(ln, SEP);
    if (cols.length < 6) continue;

    int ms;
    int st;
    try {
      ms = Integer.parseInt(cols[0]);
      st = Integer.parseInt(cols[1]);
    } catch(Exception e) {
      continue;
    }

    if (firstMs < 0) firstMs = ms;
    int tRel = ms - firstMs;
    if (tRel > lastMs) lastMs = tRel;

    String ev      = cols[2];
    String payload = cols[3];
    float gx = parseFloatSafe(cols[4]);
    float gy = parseFloatSafe(cols[5]);

    LogRow r = new LogRow();
    r.t = tRel;
    r.state = st;
    r.event = ev;
    r.payload = payload;
    r.gx = gx;
    r.gy = gy;
    logRows.add(r);

    if (ev.equals("GAZE")) {
      GazeSample gs = new GazeSample();
      gs.t  = tRel;
      gs.gx = gx;
      gs.gy = gy;
      gaze.add(gs);
    }
  }

  totalDuration = lastMs;
}

void updatePostSelectedFrom(int cond, String imgId){
  if (imgId == null || imgId.trim().isEmpty()) return;

  if (cond <= 0 && currentCond > 0) {
    cond = currentCond;
  }
  if (cond <= 0) return;

  postCond = cond;
  postSelectedId = imgId;

  postSelectedImg = getCached(postCond, postSelectedId);
}

void updateCondAnimalFromPayload(HashMap<String,String> m){
  if (m == null) return;
  if (m.containsKey("cond") && m.containsKey("animal_name")) {
    try {
      int c = Integer.parseInt(m.get("cond"));
      String animal = m.get("animal_name");
      if (animal != null && animal.trim().length() > 0) {
        condAnimalName.put(c, animal);
      }
    } catch(Exception e){}
  }
}

String folderFromId(String id){
  if (id == null) return null;
  String base = removeExt(trim(id)).toLowerCase();
  int u = base.indexOf('_');
  if (u <= 0) return null;
  return base.substring(0, u);
}

boolean folderExists(String folder){
  if (folder == null) return false;
  File d = new File(IMG_DIR + "/" + folder);
  return d.exists() && d.isDirectory();
}

void updateFolderHint(int cond, String anyId){
  if (cond <= 0 || anyId == null) return;
  String f = folderFromId(anyId);
  if (f != null && folderExists(f)) condFolderHint.put(cond, f);
}

void processRow(LogRow r) {
  int prevState = currentState;

  if (r.state >= 0) currentState = r.state;

  String ev = r.event;

  if (ev.equals("BTN_NEXT")) {
    currentState = nextStateByBtnNext(prevState);
  }

  if (ev.equals("EVENT_PARTICIPANT")) {
    HashMap<String,String> m = parsePayload(r.payload);
    if (m.containsKey("gender_idx")) {
      try { demoGenderIdx = Integer.parseInt(m.get("gender_idx")); } catch(Exception e) {}
      demoExtra.put("gender_idx", m.get("gender_idx"));
    }
    if (m.containsKey("age")) {
      demoAge = m.get("age");
      demoExtra.put("age", demoAge);
    }
  }

  if (prevState == DEMO && ev.equals("BTN_NEXT")) {
    HashMap<String,String> m = parsePayload(r.payload);
    if (m.containsKey("seh")) {
      demoExtra.put("seh", m.get("seh"));
    }
    if (m.containsKey("gender_idx") && demoGenderIdx < 0) {
      try { demoGenderIdx = Integer.parseInt(m.get("gender_idx")); } catch(Exception e){}
    }
    if (m.containsKey("age") && (demoAge == null || demoAge.isEmpty())) {
      demoAge = m.get("age");
    }
  }

  if (ev.equals("EVENT_SHOW_SET") || ev.equals("NAV_FWD") || ev.equals("NAV_BACK")) {
    HashMap<String,String> m = parsePayload(r.payload);

    updateCondAnimalFromPayload(m);

    if (m.containsKey("cond")) {
      try { currentCond = Integer.parseInt(m.get("cond")); } catch(Exception e) {}
    }
    if (m.containsKey("set")) {
      try { currentSet = Integer.parseInt(m.get("set")); } catch(Exception e) {}
    }

    if (m.containsKey("ids")) {
      currentIds = split(m.get("ids"), '|');
      if (currentIds.length > 0) updateFolderHint(currentCond, currentIds[0]);
    } else if (currentCond > 0 && currentSet >= 0) {
      currentIds = idsForCondSet(currentCond, currentSet);
      if (currentIds.length > 0) updateFolderHint(currentCond, currentIds[0]);
    } else {
      currentIds = new String[0];
    }

    loadCurrentImages();
  }

  if (ev.equals("EVENT_ZOOM_OPEN")) {
    HashMap<String,String> m = parsePayload(r.payload);

    updateCondAnimalFromPayload(m);

    if (m.containsKey("cond")) {
      try { zoomCond = Integer.parseInt(m.get("cond")); } catch(Exception e) {}
    }
    if (m.containsKey("image_id")) {
      zoomId = m.get("image_id");
      updateFolderHint(zoomCond, zoomId);
      zoomImg = getCached(zoomCond, zoomId);
    }
    zoomOpen = true;

    int c = zoomCond;
    int s = inferSetFromImageIdx(c, m);
    if (c > 0 && s >= 0 && (c != currentCond || s != currentSet)) {
      currentCond = c;
      currentSet  = s;
      currentIds  = idsForCondSet(currentCond, currentSet);
      loadCurrentImages();
    }
  }

  if (ev.equals("EVENT_ZOOM_CLOSE")) {
    zoomOpen = false;
    zoomImg = null;
    zoomId = "";
    zoomCond = -1;
  }

  if (ev.equals("EVENT_SELECT")) {
    HashMap<String,String> m = parsePayload(r.payload);

    updateCondAnimalFromPayload(m);

    int selCond = currentCond;
    int selSet  = currentSet;

    if (m.containsKey("cond")) {
      try { selCond = Integer.parseInt(m.get("cond")); } catch(Exception e) {}
    }
    if (m.containsKey("set")) {
      try { selSet = Integer.parseInt(m.get("set")); } catch(Exception e) {}
    }

    String imgId = postSelectedId;
    if (m.containsKey("image_id")) {
      imgId = m.get("image_id");
      updateFolderHint(selCond, imgId);
    }

    currentCond = selCond;
    currentSet  = selSet;

    if (currentIds == null || currentIds.length == 0) {
      currentIds = idsForCondSet(currentCond, currentSet);
      loadCurrentImages();
    }

    updatePostSelectedFrom(selCond, imgId);

    zoomOpen = false;
    zoomImg = null;
    zoomId = "";
    zoomCond = -1;

    postRating = -1;

    currentState = POST_TRIAL;
  }

  if (ev.equals("CALIB_POINT_DONE")) {
    HashMap<String,String> m = parsePayload(r.payload);
    String key = m.get("nx") + "," + m.get("ny");
    doneCalibPoints.add(key);
  }

  if (ev.equals("EVENT_POST_TRIAL")) {
  HashMap<String,String> m = parsePayload(r.payload);

  updateCondAnimalFromPayload(m);

  if (m.containsKey("q_satisfaction_1_7")) {
    try { postRating = Integer.parseInt(m.get("q_satisfaction_1_7")); } catch(Exception e) {}
  }

  int condFromPayload = postCond;
  if (m.containsKey("cond")) {
    try { condFromPayload = Integer.parseInt(m.get("cond")); } catch(Exception e) {}
  }

  String imgId = postSelectedId;
  if (m.containsKey("selected_id")) {
    imgId = m.get("selected_id");
  }

  updatePostSelectedFrom(condFromPayload, imgId);

  if (hasNextCondition()) {
    advanceToNextCondition();
    currentState = TASK;
  } else {
    currentState = FINAL_SURVEY;
  }
}

  if (ev.equals("EVENT_FINAL_FAVORITE")) {
    HashMap<String,String> m = parsePayload(r.payload);
    if (m.containsKey("fav")) {
      try { finalFavCond = Integer.parseInt(m.get("fav")); } catch(Exception e) {}
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
      String k = p.substring(0, eq).trim();
      String v = p.substring(eq+1).trim();
      map.put(k, v);
    }
  }
  return map;
}

void drawWelcomeReplay() {
  title("Willkommen");
  bodyCentered("Willkommen zur Studie. Klicke auf Weiter, um fortzufahren.");
  drawButtonCentered("Weiter", 160);
}

void drawConsentReplay() {
  title("Einverständnis & Teilnehmernummer");
  bodyLeft("Bitte Teilnehmer-Nr. eingeben und Einverständnis bestätigen.", 40, 120);

  int boxX = 40, boxY = 170, boxW = 200, boxH = 40;
  noFill();
  stroke(180);
  rect(boxX, boxY, boxW, boxH, 8);
  fill(230);
  textAlign(LEFT,TOP);
  text("Teilnehmer-Nr.", boxX+8, boxY+8);

  int cbX = 40, cbY = 230, cbS = 24;
  noFill();
  stroke(200);
  rect(cbX, cbY, cbS, cbS, 4);
  line(cbX, cbY, cbX+cbS, cbY+cbS);
  line(cbX+cbS, cbY, cbX, cbY+cbS);

  fill(220);
  textAlign(LEFT,TOP);
  text("Ich habe mein Einverständnis schriftlich bestätigt.", cbX+cbS+10, cbY+2);

  drawButtonCentered("Weiter", 160);
  textAlign(LEFT,BASELINE);
}

void drawDemoReplay() {
  title("Demografie");

  bodyLeft("Geschlecht:", 40, 140);
  String[] geschOpts = {"männlich","weiblich","divers"};
  drawRadioColumn(geschOpts, 40, 170, 40, demoGenderIdx);

  int yAfter = 170 + geschOpts.length*40 + 40;

  bodyLeft("Alter (in Jahren):", 40, yAfter);
  int boxW = 160, boxH = 36;
  noFill();
  stroke(180);
  rect(40, yAfter+30, boxW, boxH, 8);
  fill(230);
  textAlign(LEFT,TOP);
  text(demoAge==null?"":demoAge, 48, yAfter+36);

  int yAfterAge = yAfter + 100;

  bodyLeft("Tragen Sie während dieser Studie eine Sehhilfe?", 40, yAfterAge);

  String[] sehOpts = {"keine Sehhilfe", "Brille", "Kontaktlinsen"};
  int sehReplayIdx = -1;

  if (demoExtra.containsKey("seh")) {
    String s = demoExtra.get("seh");
    if (s.equals("keine Sehhilfe")) sehReplayIdx = 0;
    if (s.equals("Brille"))        sehReplayIdx = 1;
    if (s.equals("Kontaktlinsen")) sehReplayIdx = 2;
  }

  drawRadioColumn(sehOpts, 40, yAfterAge+40, 40, sehReplayIdx);

  drawButtonCentered("Weiter", 160);
  textAlign(LEFT,BASELINE);
}

void drawTaskInfoReplay() {
  title("Aufgabenstellung");
  bodyLeft(
    "Aufgabe:\n" +
    "• Sie haben die Aufgabe, für vier neue Foren des Tierschutzverbandes ein Logo auszuwählen.\n" +
    "• Dafür sehen Sie gleich Tierbilder in verschiedenen Modi (1, 4, 20, 100).\n" +
    "• Bitte wählen Sie in jedem Set das Bild aus, das Sie als Logo bevorzugen.\n" +
    "• Mit den Pfeiltasten-Buttons können Sie zwischen den Sets navigieren.\n" +
    "• Durch einen Klick auf ein Bild öffnet sich die Zoom-Ansicht.",
    40, 130
  );
  drawButtonCentered("Kalibrierung starten", 160);
}

void drawCalibReplay() {
  title("Kalibrierung");
  bodyLeft("Bitte die Punkte nacheinander anschauen, bis sie grün werden.", 40, 90);
  float[][] pts = {
    {0.08,0.08},{0.5,0.08},{0.92,0.08},
    {0.08,0.5},{0.92,0.5},
    {0.08,0.92},{0.5,0.92},{0.92,0.92}
  };
  for (float[] p : pts) {
    int cx = int(p[0] * width);
    int cy = int(p[1] * height);
    String key = p[0] + "," + p[1];
    boolean done = doneCalibPoints.contains(key);
    noStroke();
    if (done) fill(80,200,80);
    else      fill(200,60,60);
    ellipse(cx, cy, 28, 28);
  }
  drawButtonCentered("Weiter", 160);
}

void drawTaskReplay() {
  title("Aufgabe – Modus " + currentCond);
  if (zoomOpen && zoomImg != null) {
    drawCurrentGrid();
    drawZoomOverlay();
  } else {
    drawCurrentGrid();
  }
  int y = height - 90;
  if (currentCond != 100) {
    drawButton(40, y, 140, 44, "← Zurück");
    drawButton(width - 240, y, 180, 44, "→ Weiter");
  }
}

void drawPostTrialReplay() {
  title("Kurze Bewertung");
  int imgAreaTop = 100;
  int imgAreaH   = int(height * 0.4);
  if (postSelectedImg != null) {
    imageMode(CENTER);
    float maxW = width * 0.6;
    float maxH = imgAreaH;
    float s = min(maxW / postSelectedImg.width, maxH / postSelectedImg.height);
    int dw = int(postSelectedImg.width * s);
    int dh = int(postSelectedImg.height * s);
    image(postSelectedImg, width/2, imgAreaTop + imgAreaH/2, dw, dh);
  } else {
    bodyCentered("Kein ausgewähltes Bild geladen.");
  }
  int qY = imgAreaTop + imgAreaH + 40;
  bodyLeft("Wie zufrieden sind Sie mit Ihrer Auswahl? (1 = gar nicht, 7 = sehr)", 40, qY);
  drawLikert7(40, qY+50, postRating);
  drawButtonCentered("Weiter", 80);
}

void drawFinalSurveyReplay() {
  title("Abschluss");

  bodyLeft("Mit welchem Modus würden Sie am liebsten weiterarbeiten?", 40, 140);
  String[] favs = {"1 Bild","4 Bilder","20 Bilder","100 Bilder"};
  int favIdx = -1;
  if (finalFavCond == 1)   favIdx = 0;
  if (finalFavCond == 4)   favIdx = 1;
  if (finalFavCond == 20)  favIdx = 2;
  if (finalFavCond == 100) favIdx = 3;
  drawRadioRow(favs, 40, 170, favIdx);

  drawButtonCentered("Abschließen", 160);
}

void drawThanksReplay() {
  title("Vielen Dank!");
  bodyCentered("Die Teilnahme ist beendet.");
  drawButtonCentered("Beenden", 160);
}

void drawUnknownReplay() {
  title("Unbekannter Zustand: " + currentState);
  bodyCentered("Kein Layout für diesen Zustand.");
}

void loadCurrentImages() {
  if (currentIds == null) {
    currentImgs = new PImage[0];
    return;
  }
  currentImgs = new PImage[currentIds.length];
  for (int i = 0; i < currentIds.length; i++) {
    currentIds[i] = resolveIdForCond(currentCond, currentIds[i]);
    currentImgs[i] = getCached(currentCond, currentIds[i]);
  }
}

void drawCurrentGrid() {
  if (currentCond <= 0 || currentImgs == null || currentImgs.length == 0) {
    bodyCentered("Keine Stimuli geladen.");
    return;
  }
  if (currentCond == 1) {
    drawSingle();
  } else if (currentCond == 4) {
    drawGridN(2,2);
  } else if (currentCond == 20) {
    drawGridN(5,4);
  } else if (currentCond == 100) {
    drawGridN(10,10);
  } else {
    drawGridN(2,2);
  }
}

void drawSingle() {
  int imgAreaTop = 100;
  int imgAreaH   = int(height * 0.7);
  PImage img = currentImgs.length>0 ? currentImgs[0] : null;
  if (img == null) {
    bodyCentered("Bild konnte nicht geladen werden.");
    return;
  }
  imageMode(CENTER);
  float maxW = width * 0.6;
  float maxH = imgAreaH;
  float s = min(maxW / img.width, maxH / img.height);
  int dw = int(img.width * s);
  int dh = int(img.height * s);
  image(img, width/2, imgAreaTop + imgAreaH/2, dw, dh);
  drawButtonCentered("Select", 80);
}

void drawGridN(int cols, int rows) {
  imageMode(CENTER);

  if (cols == 10 && rows == 10) {
    int top = 90;
    int bottomMargin = 50;

    int maxGridH = height - top - bottomMargin;

    float widthFactor = 0.85f;
    int targetGridW = int(width * widthFactor);

    float targetAspect = 16.0f / 9.0f;

    int cellW = targetGridW / cols;
    int cellH = int(cellW / targetAspect);

    int gridH = cellH * rows;

    if (gridH > maxGridH){
      float scale = (float)maxGridH / (float)gridH;
      cellW = int(cellW * scale);
      cellH = int(cellH * scale);
      gridH = cellH * rows;
    }

    int gridW = cellW * cols;

    int startX = (width - gridW) / 2;

    int innerPad = 4;

    for (int i = 0; i < currentImgs.length && i < cols*rows; i++) {
      int c = i % cols;
      int r = i / cols;

      int xRect = startX + c * cellW + innerPad/2;
      int yRect = top    + r * cellH + innerPad/2;
      int wRect = cellW - innerPad;
      int hRect = cellH - innerPad;

      noFill();
      stroke(80);
      rect(xRect, yRect, wRect, hRect, 10);

      PImage img = currentImgs[i];
      if (img != null) {
        float s = min((float)wRect / img.width, (float)hRect / img.height);
        int dw = int(img.width * s);
        int dh = int(img.height * s);
        int cx = xRect + wRect/2;
        int cy = yRect + hRect/2;
        image(img, cx, cy, dw, dh);
      } else {
        fill(200); noStroke();
        textAlign(CENTER,CENTER);
        text("Bild fehlt", xRect + wRect/2, yRect + hRect/2);
        textAlign(LEFT,BASELINE);
      }
    }

  } else {
    int margin = 20;
    int top = 100;

    int gridW = width - margin*2;
    int gridH = height - top - margin - 120;

    int cellW = gridW / cols;
    int cellH = gridH / rows;

    for (int i=0; i<currentImgs.length && i<cols*rows; i++) {
      int c = i % cols;
      int r = i / cols;

      int xRect = margin + c * cellW + 10;
      int yRect = top    + r * cellH + 10;
      int wRect = cellW - 20;
      int hRect = cellH - 20;

      noFill();
      stroke(80);
      rect(xRect, yRect, wRect, hRect, 10);

      PImage img = currentImgs[i];
      if (img != null) {
        float s = min((float)wRect / img.width, (float)hRect / img.height);
        int dw = int(img.width * s);
        int dh = int(img.height * s);
        int cx = xRect + wRect/2;
        int cy = yRect + hRect/2;
        image(img, cx, cy, dw, dh);
      } else {
        fill(200); noStroke();
        textAlign(CENTER,CENTER);
        text("Bild fehlt", xRect + wRect/2, yRect + hRect/2);
        textAlign(LEFT,BASELINE);
      }
    }
  }
}

void drawZoomOverlay() {
  fill(0,180);
  noStroke();
  rect(0,0,width,height);
  if (zoomImg != null) {
    imageMode(CENTER);
    float maxW = width * 0.8;
    float maxH = height * 0.8;
    float s = min(maxW / zoomImg.width, maxH / zoomImg.height);
    int dw = int(zoomImg.width * s);
    int dh = int(zoomImg.height * s);
    image(zoomImg, width/2, height/2, dw, dh);
  }
  fill(240);
  textAlign(LEFT,TOP);
  text("ID: " + zoomId, 40, 40);
  drawButton(width/2-100, height-90, 200, 56, "Select");
  drawButton(40, 40, 160, 44, "Schließen");
  textAlign(LEFT,BASELINE);
}

void drawGazeTrail() {
  if (gaze.isEmpty()) return;

  float t0 = replayT - trailMs;
  if (t0 < 0) t0 = 0;

  ArrayList<GazeSample> trail = new ArrayList<GazeSample>();
  for (GazeSample gs : gaze) {
    if (gs.t >= t0 && gs.t <= replayT) trail.add(gs);
  }
  if (trail.isEmpty()) return;

  strokeWeight(2);
  for (int i=1; i<trail.size(); i++) {
    GazeSample a = trail.get(i-1);
    GazeSample b = trail.get(i);

    float ageA = (replayT - a.t) / trailMs;
    float ageB = (replayT - b.t) / trailMs;
    float alphaA = map(ageA, 0, 1, 255, 0);
    float alphaB = map(ageB, 0, 1, 255, 0);

    stroke(0, 255, 0, (alphaA + alphaB) * 0.5);
    line(a.gx * width, a.gy * height, b.gx * width, b.gy * height);
  }

  GazeSample last = trail.get(trail.size()-1);
  noStroke();
  fill(0,255,0);
  ellipse(last.gx * width, last.gy * height, 14, 14);
}

void title(String s){
  fill(240);
  textAlign(CENTER,TOP);
  textSize(28);
  text(s, width/2, 20);
  textSize(18);
  textAlign(LEFT,BASELINE);
}

void bodyCentered(String s){
  fill(210);
  textAlign(CENTER,TOP);
  textSize(20);
  text(s, width/2, 120);
  textAlign(LEFT,BASELINE);
  textSize(18);
}

void bodyLeft(String s, int x, int y){
  fill(210);
  textAlign(LEFT,TOP);
  textSize(18);
  text(s, x, y);
  textAlign(LEFT,BASELINE);
}

void drawLikert7(int x, int y, int sel){
  int r = 12;
  int step = 40;
  textSize(16);
  for (int i=1;i<=7;i++){
    int cx = x + (i-1)*step;
    int cy = y;
    noFill();
    stroke(sel==i ? color(80,200,255) : color(180));
    strokeWeight(2);
    ellipse(cx, cy, 2*r, 2*r);
    if (sel==i){
      noStroke(); fill(80,200,255); ellipse(cx, cy, r, r);
    }
    fill(230);
    textAlign(CENTER,TOP);
    text(i, cx, y + r + 6);
  }
  textAlign(LEFT,BASELINE);
  textSize(18);
}

void drawRadioColumn(String[] opts, int x, int y, int step, int sel){
  for (int i=0;i<opts.length;i++){
    int r=10;
    int cx=x+r;
    int cy=y+i*step+r;
    noFill();
    stroke(sel==i? color(80,200,255): color(180));
    strokeWeight(2);
    ellipse(cx,cy,2*r,2*r);
    if (sel==i){
      noStroke();
      fill(80,200,255);
      ellipse(cx,cy,r,r);
    }
    fill(230);
    textAlign(LEFT,TOP);
    text(opts[i], x+2*r+10, cy+6);
  }
  textAlign(LEFT,BASELINE);
}

void drawRadioRow(String[] opts, int x, int y, int sel){
  int bx=x;
  for (int i=0;i<opts.length;i++){
    int w=max(160, int(textWidth(opts[i])+36));
    noStroke();
    fill(sel==i?120:60);
    rect(bx, y, w, 36, 8);
    fill(240);
    textAlign(CENTER,CENTER);
    text(opts[i], bx+w/2, y+18);
    textAlign(LEFT,BASELINE);
    bx+=w+12;
  }
}

void drawButtonCentered(String label, int yOff){
  int w=220,h=48;
  int x=width/2-w/2;
  int y=height - yOff;
  noStroke();
  fill(60,160,90);
  rect(x,y,w,h,8);
  fill(255);
  textAlign(CENTER,CENTER);
  text(label, x+w/2, y+h/2);
  textAlign(LEFT,BASELINE);
}

void drawButton(int x, int y, int w, int h, String label){
  noStroke();
  fill(60,160,90);
  rect(x,y,w,h,8);
  fill(255);
  textAlign(CENTER,CENTER);
  text(label, x+w/2, y+h/2);
  textAlign(LEFT,BASELINE);
}

void drawOverlay() {
  fill(255);
  textAlign(LEFT,TOP);
  textSize(14);
  text("Replay: " + int(replayT) + " / " + totalDuration + " ms", 20, 20);
  text("Speed: " + nf(speed,1,1) + "x  (+ / -)", 20, 38);
  text("State: " + currentStateName(), 20, 56);
  text("Teilnehmer: " + PARTICIPANT, 20, 74);
  text("Pause: " + (paused ? "ja (Leertaste)" : "nein (Leertaste)"), 20, 92);
  textAlign(LEFT,BASELINE);
}

String currentStateName() {
  if (currentState == WELCOME) return "WELCOME";
  if (currentState == CONSENT) return "CONSENT";
  if (currentState == DEMO) return "DEMO";
  if (currentState == TASKINFO) return "TASKINFO";
  if (currentState == CALIB) return "CALIB";
  if (currentState == TASK) return "TASK";
  if (currentState == POST_TRIAL) return "POST_TRIAL";
  if (currentState == FINAL_SURVEY) return "FINAL_SURVEY";
  if (currentState == THANKS) return "THANKS";
  return str(currentState);
}

float parseFloatSafe(String s){
  try { return Float.parseFloat(s); } catch(Exception e){ return Float.NaN; }
}

void keyPressed() {
  if (key == '+') {
    speed *= 1.5;
  } else if (key == '-') {
    speed /= 1.5;
    if (speed < 0.1) speed = 0.1;
  } else if (key == '0') {
    replayT = 0;
    nextLogIdx = 0;
    currentState = WELCOME;
    currentCond = -1;
    currentSet = -1;
    zoomOpen = false;
    zoomImg = null;
    zoomId = "";
    zoomCond = -1;
    paused = false;
    postRating = -1;
    postCond = -1;
    postSelectedId = "";
    postSelectedImg = null;
    finalFavCond = -1;
    demoGenderIdx = -1;
    demoAge = "";
    demoExtra.clear();
    doneCalibPoints.clear();
    condAnimalName.clear();

    buildCondAnimalNameFromLogs();

    participantNo = parseParticipantNoFromName(PARTICIPANT);
    if (participantNo < 0) participantNo = 0;
    initOrderFromParticipantNo(participantNo);

    prepareReplayPreload();

  } else if (key == ' ') {
    paused = !paused;
  }
}

String folderForCond(int cond){
  String animal = condAnimalName.get(cond);
  if (animal != null && animal.trim().length() > 0) {
    String f = animal.trim().toLowerCase();
    if (folderExists(f)) return f;
  }

  String hint = condFolderHint.get(cond);
  if (hint != null && folderExists(hint)) return hint;

  if (cond == 1 && folderExists("katze")) return "katze";
  if (cond == 4 && folderExists("hund")) return "hund";
  if (cond == 20 && folderExists("pferd")) return "pferd";
  if (cond == 100 && folderExists("hase")) return "hase";

  return "hase";
}
