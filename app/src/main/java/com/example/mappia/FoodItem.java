package com.example.mappia;

public class FoodItem {
    private final int id;
    private final String name;
    private final int imageResId;
    private final double price;

    public FoodItem(int id, String name, int imageResId, double price) {
        this.id = id;
        this.name = name;
        this.imageResId = imageResId;
        this.price = price;
    }

    public int getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public int getImageResId() {
        return imageResId;
    }

    public double getPrice() {
        return price;
    }

    @Override
    public String toString() {
        return name + " ($" + price + ")";
    }
} 