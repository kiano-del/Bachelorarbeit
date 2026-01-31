import java.io.PrintWriter; //<>//
import java.io.File;
import java.util.Collections;

final String FILE_PATH = "C:/Users/kiano/Uni/Bachelor/Bachelor-Arbeit/Processing_Projekte/UmfrageErgebnisse/Teilnehmer4/raw04.csv"; 
final char SEP = ';';

final int SCREEN_W = 1920;
final int SCREEN_H = 1080;

final int MIN_FIXATION_DURATION = 150; 
final float MAX_DISPERSION_PX = 100;
final int MAX_GAP_MS = 500; 

final int HIT_PADDING_STD = 30;
final int HIT_PADDING_100 = 5; 

final String[] MASTER_ANIMALS = { "Katze", "Hund", "Pferd", "Hase" };
final int[][] LATIN_SQUARE = {
  {1, 4, 20, 100},
  {4, 20, 100, 1},
  {20, 100, 1, 4},
  {100, 1, 4, 20}
};

void setup() {
  Analysis analysis = new Analysis();
  String[] lines = loadStrings(FILE_PATH);
  
  if (lines == null) { exit(); return; }

  int pNo = extractParticipantID(FILE_PATH);
  int latinIdx = pNo % 4;
  int[] currentCondOrder = LATIN_SQUARE[latinIdx];
  int block = pNo / 4;
  String[] currentAnimalOrder = new String[4];
  for (int pos = 0; pos < 4; pos++) {
    int animalIdx = (pos + block) % MASTER_ANIMALS.length;
    currentAnimalOrder[pos] = MASTER_ANIMALS[animalIdx];
  }
  
  println("Starte Analyse für P" + pNo);

  int currentMode = -1;
  String currentAnimal = ""; 
  ArrayList<String> currentGridImages = new ArrayList<String>();
  String activeZoomImage = "";
  
  int taskIndex = -1; 
  boolean taskActive = false; 
  
  long lastGazeTime = 0;
  long lastLineTime = 0;
  
  String fixStartImage = "";
  long fixStart = 0;
  float fixSumX = 0, fixSumY = 0;
  int fixCount = 0;
  String lastTargetImage = ""; 
  
  for (int i = 1; i < lines.length; i++) {
    String[] parts = split(lines[i], SEP);
    if (parts.length < 6) continue;
    
    long currentLineTime = 0;
    try { currentLineTime = Long.parseLong(parts[0].trim()); } catch(Exception e) { continue; }

    String event = parts[2];
    String payload = parts[3];
    
    float gx = Float.NaN, gy = Float.NaN;
    if (parts[4].length() > 0) gx = float(parts[4]);
    if (parts[5].length() > 0) gy = float(parts[5]);

    if (payload.contains("from=calibration")) {
       taskIndex = 0; 
       currentMode = currentCondOrder[0];
       currentAnimal = currentAnimalOrder[0];
       generateFallbackGrid(currentGridImages, currentAnimal, currentMode);
       taskActive = true;
    }
    else if (event.equals("EVENT_SELECT")) { 
       taskActive = false;
       fixCount = 0; 
    }
    else if (event.equals("EVENT_POST_TRIAL")) {
       taskIndex++; 
       if (taskIndex < 4) {
           currentMode = currentCondOrder[taskIndex];
           currentAnimal = currentAnimalOrder[taskIndex];
           generateFallbackGrid(currentGridImages, currentAnimal, currentMode);
           taskActive = true; 
           lastTargetImage = ""; 
           fixCount = 0;
           activeZoomImage = "";
       } else {
           taskActive = false;
       }
    }
    else if (event.equals("EVENT_ZOOM_CLOSE")) {
       activeZoomImage = ""; 
       if (taskIndex < 4) taskActive = true;    
    }
    else if (event.equals("BTN_NEXT")) {
       activeZoomImage = "";
    }
    
    if (event.equals("NAV_FWD") || event.equals("NAV_BACK")) {
       if (payload.contains("ids=")) {
          String idsStr = extractString(payload, "ids");
          String[] idsArr = split(idsStr, '|');
          currentGridImages.clear();
          for(String s : idsArr) currentGridImages.add(s);
       }
       if (payload.contains("cond=")) {
           int c = extractInt(payload, "cond");
           if (c != -1 && taskIndex < 4 && currentCondOrder[taskIndex] == c) {
               currentMode = c;
               taskActive = true;
           }
       }
    }

    long duration = 0;
    long gap = (lastLineTime == 0) ? 0 : (currentLineTime - lastLineTime);
    lastLineTime = currentLineTime;
    
    if (event.equals("GAZE")) {
       if (lastGazeTime != 0) {
          duration = currentLineTime - lastGazeTime;
          if (duration < 0) duration = 0;
          if (duration > 500) duration = 0; 
       }
       lastGazeTime = currentLineTime;
    } 

    if (currentMode == -1 || !taskActive) {
      fixCount = 0; 
      continue;
    }
    
    String targetImage = "";
    if (activeZoomImage.length() > 0) {
       targetImage = activeZoomImage;
    } else {
       if (event.equals("GAZE") && !Float.isNaN(gx) && !Float.isNaN(gy) && currentGridImages.size() > 0) {
          targetImage = getGridHitExact(gx, gy, currentMode, currentGridImages);
       }
    }
    
    if (targetImage.length() > 0) {
       ModeStats modeStats = analysis.getMode(currentMode);
       ImageStats imgStats = modeStats.getImage(targetImage);
       
       if (!targetImage.equals(lastTargetImage)) {
          imgStats.viewCount++;
       }
       imgStats.totalDurationMs += duration;
       
       if (event.equals("GAZE") && !Float.isNaN(gx) && !Float.isNaN(gy)) {
          
          if (gap > MAX_GAP_MS && fixCount > 0) {
             long fixEndTime = currentLineTime - gap;
             long fixDur = fixEndTime - fixStart; 
             
             if (fixDur >= MIN_FIXATION_DURATION) {
                analysis.getMode(currentMode).getImage(fixStartImage).fixationCount++;
                analysis.getMode(currentMode).getImage(fixStartImage).totalFixationDuration += fixDur;
             }
             fixCount = 0;
          }

          float xPx = gx * SCREEN_W;
          float yPx = gy * SCREEN_H;
          
          if (fixCount == 0) {
             fixStart = currentLineTime;
             fixStartImage = targetImage;
             fixSumX = gx; fixSumY = gy;
             fixCount = 1;
          } else {
             float currentAvgX = fixSumX / fixCount;
             float currentAvgY = fixSumY / fixCount;
             float distPx = dist(xPx, yPx, currentAvgX * SCREEN_W, currentAvgY * SCREEN_H);
             
             if (distPx < MAX_DISPERSION_PX && targetImage.equals(fixStartImage)) {
                fixSumX += gx; fixSumY += gy;
                fixCount++;
             } else {
                long fixEndTime = currentLineTime - gap;
                long fixDur = fixEndTime - fixStart;
                
                if (fixDur >= MIN_FIXATION_DURATION && fixDur < 10000) {
                   ImageStats startStats = modeStats.getImage(fixStartImage);
                   startStats.fixationCount++;
                   startStats.totalFixationDuration += fixDur;
                }
                fixStart = currentLineTime;
                fixStartImage = targetImage;
                fixSumX = gx; fixSumY = gy;
                fixCount = 1;
             }
          }
       }
    } else {
       if (fixCount > 0) {
           long fixEndTime = currentLineTime - gap;
           long fixDur = fixEndTime - fixStart;
           if (fixDur >= MIN_FIXATION_DURATION && fixStartImage.length() > 0 && fixDur < 10000) {
               if (analysis.getMode(currentMode) != null) {
                 ImageStats startStats = analysis.getMode(currentMode).getImage(fixStartImage);
                 startStats.fixationCount++;
                 startStats.totalFixationDuration += fixDur;
               }
           }
       }
       fixCount = 0; 
       fixStartImage = "";
    }
    
    lastTargetImage = targetImage;
  }
  
  String outputName = "ergebnisse_" + split(FILE_PATH, '/')[split(FILE_PATH, '/').length - 1];
  analysis.saveResults(outputName);
  exit();
}

int extractParticipantID(String path) {
  File f = new File(path);
  String name = f.getName().toLowerCase(); 
  String numberOnly = name.replaceAll("[^0-9]", "");
  if (numberOnly.length() > 0) return int(numberOnly);
  return 0; 
}

int getIndexForMode(int mode, int[] order) {
  for(int i=0; i<order.length; i++) if(order[i] == mode) return i;
  return -1;
}

void generateFallbackGrid(ArrayList<String> list, String animal, int count) {
  list.clear();
  String base = animal.toLowerCase(); 
  for (int i = 1; i <= count; i++) {
    list.add(base + "_" + nf(i, 3) + ".png");
  }
}

String getGridHitExact(float gx, float gy, int mode, ArrayList<String> images) {
  int cols = 1, rows = 1;
  float currentPadding = 0;
  float xPx = gx * SCREEN_W;
  float yPx = gy * SCREEN_H;

  if (mode == 1) {
    if (images.size() < 1) return "";
    float imgW = SCREEN_W * 0.6;
    float imgH = SCREEN_H * 0.6;
    float centerX = SCREEN_W / 2.0;
    float centerY = (SCREEN_H / 2.0) - 20;
    currentPadding = HIT_PADDING_STD;
    if (xPx >= (centerX - imgW/2 - currentPadding) && xPx <= (centerX + imgW/2 + currentPadding) &&
        yPx >= (centerY - imgH/2 - currentPadding) && yPx <= (centerY + imgH/2 + currentPadding)) return images.get(0);
    return "";
  }
  
  if (mode == 4)       { cols = 2; rows = 2; currentPadding = HIT_PADDING_STD; } 
  else if (mode == 20) { cols = 5; rows = 4; currentPadding = HIT_PADDING_STD; } 
  else if (mode == 100){ cols = 10; rows = 10; currentPadding = HIT_PADDING_100; } 
  else return ""; 
  
  if (mode == 100) {
      int top = 90; int bottomMargin = 50;
      float maxGridH = SCREEN_H - top - bottomMargin;
      float widthFactor = 0.85;
      float targetGridW = SCREEN_W * widthFactor;
      float targetAspect = 16.0 / 9.0;
      float cellW = targetGridW / cols;
      float cellH = cellW / targetAspect;
      float gridH = cellH * rows;
      if (gridH > maxGridH){
        float scale = maxGridH / gridH;
        cellW = cellW * scale;
        cellH = cellH * scale;
      }
      float gridW = cellW * cols;
      float startX = (SCREEN_W - gridW) / 2.0;
      float innerPad = 4; 
      for (int r = 0; r < rows; r++){
        for (int c = 0; c < cols; c++){
          int idx = r * cols + c;
          if (idx >= images.size()) break;
          float boxX = startX + c * cellW + innerPad/2;
          float boxY = top    + r * cellH + innerPad/2;
          float boxW = cellW - innerPad;
          float boxH = cellH - innerPad;
          if (xPx >= (boxX - currentPadding) && xPx <= (boxX + boxW + currentPadding) &&
              yPx >= (boxY - currentPadding) && yPx <= (boxY + boxH + currentPadding)) return images.get(idx);   
        }
      }
  } else {
      int margin = 20; int top = 100;
      float gridW = SCREEN_W - (margin * 2);
      float cellW = gridW / cols;
      float cellH = (float)(SCREEN_H - top - margin - 120) / rows;
      for (int r = 0; r < rows; r++){
        for (int c = 0; c < cols; c++){
          int idx = r * cols + c;
          if (idx >= images.size()) break;
          float boxX = margin + c * cellW + 10;
          float boxY = top    + r * cellH + 10;
          float boxW = cellW - 20; 
          float boxH = cellH - 20;
          if (xPx >= (boxX - currentPadding) && xPx <= (boxX + boxW + currentPadding) &&
              yPx >= (boxY - currentPadding) && yPx <= (boxY + boxH + currentPadding)) return images.get(idx);   
        }
      }
  }
  return "";
}

class Analysis {
  HashMap<Integer, ModeStats> modes = new HashMap<Integer, ModeStats>();
  
  ModeStats getMode(int id) {
    if (!modes.containsKey(id)) modes.put(id, new ModeStats(id));
    return modes.get(id);
  }
  
  void saveResults(String filename) {
    PrintWriter output = createWriter(filename);
    output.println("Modus;Bildname;Anzahl_Betrachtungen;Dauer_ms;Fixationen_Anzahl;Fixationen_Dauer_Summe");
    
    ArrayList<Integer> sortedModeIds = new ArrayList<Integer>(modes.keySet());
    Collections.sort(sortedModeIds);
    
    for (int i = 0; i < sortedModeIds.size(); i++) {
      int modeId = sortedModeIds.get(i);
      ModeStats m = modes.get(modeId);
      
      ArrayList<String> sortedImageNames = new ArrayList<String>(m.images.keySet());
      Collections.sort(sortedImageNames);
      
      for (String imgName : sortedImageNames) {
        ImageStats img = m.images.get(imgName);
        String line = m.id + ";" + img.name + ";" + img.viewCount + ";" + img.totalDurationMs + ";" + img.fixationCount + ";" + img.totalFixationDuration;
        output.println(line);
      }
      
      if (i < sortedModeIds.size() - 1) {
        output.println("");
        output.println("");
      }
    }
    
    output.flush(); output.close();
    println("Datei gespeichert: " + filename);
  }
}

class ModeStats {
  int id; HashMap<String, ImageStats> images = new HashMap<String, ImageStats>();
  ModeStats(int id) { this.id = id; }
  ImageStats getImage(String name) {
    if (!images.containsKey(name)) images.put(name, new ImageStats(name)); return images.get(name);
  }
}

class ImageStats {
  String name; long totalDurationMs = 0; int viewCount = 0; int fixationCount = 0; long totalFixationDuration = 0;
  ImageStats(String name) { this.name = name; }
}

int extractInt(String payload, String key) {
  String val = extractString(payload, key); if (val.equals("")) return -1; return int(val);
}

String extractString(String payload, String key) {
  String[] pairs = split(payload, ',');
  for (String p : pairs) { String[] kv = split(p, '='); if (kv.length == 2 && kv[0].trim().equals(key)) return kv[1].trim(); }
  return "";
}
