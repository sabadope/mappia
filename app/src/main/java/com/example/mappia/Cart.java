package com.example.mappia;

import java.util.HashMap;
import java.util.Map;

public class Cart {
    private static Cart instance;
    private final Map<FoodItem, Integer> items;

    private Cart() {
        items = new HashMap<>();
    }

    public static Cart getInstance() {
        if (instance == null) {
            instance = new Cart();
        }
        return instance;
    }

    public void addItem(FoodItem item) {
        int count = items.containsKey(item) ? items.get(item) : 0;
        items.put(item, count + 1);
    }

    public void removeItem(FoodItem item) {
        if (items.containsKey(item)) {
            int count = items.get(item);
            if (count > 1) {
                items.put(item, count - 1);
            } else {
                items.remove(item);
            }
        }
    }

    public Map<FoodItem, Integer> getItems() {
        return items;
    }

    public double getTotalPrice() {
        double total = 0;
        for (Map.Entry<FoodItem, Integer> entry : items.entrySet()) {
            total += entry.getKey().getPrice() * entry.getValue();
        }
        return total;
    }

    public void clear() {
        items.clear();
    }
} 