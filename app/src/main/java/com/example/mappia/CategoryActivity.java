package com.example.mappia;

import android.content.Intent;
import android.os.Bundle;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Button;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;

public class CategoryActivity extends AppCompatActivity {
    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_category);

        ImageView imageCategory = findViewById(R.id.imageCategoryDetail);
        TextView textCategoryName = findViewById(R.id.textCategoryNameDetail);
        Button buttonBack = findViewById(R.id.buttonBack);

        Intent intent = getIntent();
        int imageResId = intent.getIntExtra("imageResId", 0);
        String name = intent.getStringExtra("name");

        imageCategory.setImageResource(imageResId);
        textCategoryName.setText(name);

        buttonBack.setOnClickListener(v -> finish());
    }
} 