import com.intellij.util.io.storage.RecordIdIterator;
import com.intellij.util.io.storage.Storage;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.zip.InflaterInputStream;

public class StorageScan {
    private static final List<String> TERMS = Arrays.asList(
            "ga_text_scirpt_for_fork",
            "ga_text_scirpt_for_lift",
            "function ga_text_scirpt_for_fork",
            "function ga_text_scirpt_for_lift",
            "MES_Order_System_text_for_fork",
            "MES_Order_System_text_for_lift",
            "evaluate_and_plot_moea",
            "ga_schedule_optimizer_update",
            "ga_schedule_optimizer_standard",
            "ga_schedule_optimizer_update_standard",
            "binaryMap = create_binary_grid_map",
            "global mapW mapH",
            "Pareto Front Comparison"
    );

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.out.println("Usage: StorageScan <storageBasePath> <outputDir>");
            return;
        }

        Path storageBase = Path.of(args[0]);
        Path outputDir = Path.of(args[1]);
        Files.createDirectories(outputDir);

        List<String> log = new ArrayList<>();
        int scanned = 0;
        int hits = 0;

        try (Storage storage = new Storage(storageBase)) {
            RecordIdIterator iterator = storage.createRecordIdIterator();
            while (iterator.hasNextId()) {
                int id = iterator.nextId();
                if (!iterator.validId()) {
                    continue;
                }
                scanned++;

                byte[] raw;
                try (DataInputStream in = storage.readStream(id)) {
                    raw = in.readAllBytes();
                } catch (Throwable t) {
                    continue;
                }

                if (raw.length == 0) {
                    continue;
                }

                List<String> matched = new ArrayList<>();
                String rawUtf8 = new String(raw, StandardCharsets.UTF_8);
                for (String term : TERMS) {
                    if (rawUtf8.contains(term)) {
                        matched.add("raw:" + term);
                    }
                }

                byte[] inflated = tryInflate(raw);
                String inflatedUtf8 = null;
                if (inflated != null && inflated.length > 0) {
                    inflatedUtf8 = new String(inflated, StandardCharsets.UTF_8);
                    for (String term : TERMS) {
                        if (inflatedUtf8.contains(term)) {
                            matched.add("inflated:" + term);
                        }
                    }
                }

                if (matched.isEmpty()) {
                    continue;
                }

                hits++;
                String baseName = String.format("record_%06d", id);
                Files.write(outputDir.resolve(baseName + ".raw.bin"), raw);
                Files.writeString(outputDir.resolve(baseName + ".raw.txt"), rawUtf8, StandardCharsets.UTF_8);
                if (inflated != null && inflated.length > 0) {
                    Files.write(outputDir.resolve(baseName + ".inflated.bin"), inflated);
                    Files.writeString(outputDir.resolve(baseName + ".inflated.txt"), inflatedUtf8, StandardCharsets.UTF_8);
                }
                String line = baseName + " len=" + raw.length + " " + String.join(", ", matched);
                log.add(line);
                System.out.println("HIT " + line);
            }
        }

        StringBuilder sb = new StringBuilder();
        sb.append("Scanned=").append(scanned).append(", Hits=").append(hits).append(System.lineSeparator());
        for (String line : log) {
            sb.append(line).append(System.lineSeparator());
        }
        Files.writeString(outputDir.resolve("storage_scan_log.txt"), sb.toString(), StandardCharsets.UTF_8);
        System.out.println("Done. Scanned=" + scanned + ", Hits=" + hits);
    }

    private static byte[] tryInflate(byte[] raw) {
        try (InflaterInputStream in = new InflaterInputStream(new ByteArrayInputStream(raw));
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
                if (out.size() > 8 * 1024 * 1024) {
                    break;
                }
            }
            return out.toByteArray();
        } catch (IOException ignored) {
            return null;
        }
    }
}
