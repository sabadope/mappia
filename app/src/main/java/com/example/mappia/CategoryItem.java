package com.example.mappia;

public class CategoryItem {
    private final int imageResId;
    private final String name;

    public CategoryItem(int imageResId, String name) {
        this.imageResId = imageResId;
        this.name = name;
    }

    public int getImageResId() {
        return imageResId;
    }

    public String getName() {
        return name;
    }
} 