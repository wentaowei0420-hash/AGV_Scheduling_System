import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Arrays;

public class ReflectClass {
    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            System.err.println("Usage: ReflectClass <fqcn>");
            return;
        }

        Class<?> cls = Class.forName(args[0]);
        System.out.println("CLASS " + cls.getName());
        System.out.println("-- Constructors --");
        for (Constructor<?> c : cls.getDeclaredConstructors()) {
            System.out.println(c);
        }
        System.out.println("-- Fields --");
        for (Field f : cls.getDeclaredFields()) {
            System.out.println(f);
        }
        System.out.println("-- Methods --");
        Method[] methods = cls.getDeclaredMethods();
        Arrays.sort(methods, (a, b) -> a.getName().compareTo(b.getName()));
        for (Method m : methods) {
            System.out.println(m);
        }
    }
}
