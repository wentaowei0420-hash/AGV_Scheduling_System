import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.zip.InflaterInputStream;

public class LocalHistoryRecover {
    private static final Set<Integer> VALID_SECOND_BYTES =
            new HashSet<>(Arrays.asList(0x01, 0x5E, 0x9C, 0xDA));

    private static final List<String> TERMS = Arrays.asList(
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
            System.out.println("Usage: LocalHistoryRecover <storageData.bin> <outputDir>");
            return;
        }

        Path storagePath = Path.of(args[0]);
        Path outputDir = Path.of(args[1]);
        Files.createDirectories(outputDir);

        byte[] bytes = Files.readAllBytes(storagePath);
        System.out.println("Loaded " + bytes.length + " bytes from " + storagePath);

        int candidates = 0;
        int hits = 0;
        List<String> log = new ArrayList<>();

        for (int i = 0; i < bytes.length - 1; i++) {
            if ((bytes[i] & 0xFF) != 0x78 || !VALID_SECOND_BYTES.contains(bytes[i + 1] & 0xFF)) {
                continue;
            }
            candidates++;

            try {
                byte[] raw = inflate(bytes, i);
                if (raw.length == 0) {
                    continue;
                }

                String text = new String(raw, StandardCharsets.UTF_8);
                List<String> matched = new ArrayList<>();
                for (String term : TERMS) {
                    if (text.contains(term)) {
                        matched.add(term);
                    }
                }
                if (matched.isEmpty()) {
                    continue;
                }

                hits++;
                String baseName = String.format("hit_%04d_offset_%d", hits, i);
                Files.writeString(outputDir.resolve(baseName + ".txt"), text, StandardCharsets.UTF_8);
                Files.write(outputDir.resolve(baseName + ".bin"), raw);
                String line = baseName + ": " + String.join(", ", matched);
                log.add(line);
                System.out.println("HIT " + line);
            } catch (Throwable ignored) {
                // Skip invalid or non-zlib streams.
            }
        }

        StringBuilder summary = new StringBuilder();
        summary.append("Candidates=").append(candidates).append(", Hits=").append(hits).append(System.lineSeparator());
        for (String line : log) {
            summary.append(line).append(System.lineSeparator());
        }
        Files.writeString(outputDir.resolve("scan_log.txt"), summary.toString(), StandardCharsets.UTF_8);
        System.out.println("Done. Candidates=" + candidates + ", Hits=" + hits);
        System.out.println("Results written to " + outputDir);
    }

    private static byte[] inflate(byte[] bytes, int offset) throws IOException {
        try (InputStream in = new InflaterInputStream(new ByteArrayInputStream(bytes, offset, bytes.length - offset));
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
                if (out.size() > 8 * 1024 * 1024) {
                    break;
                }
            }
            return out.toByteArray();
        }
    }
}
