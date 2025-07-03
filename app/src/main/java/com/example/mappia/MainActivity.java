package com.example.mappia;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.widget.ImageView;
import android.widget.LinearLayout;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.viewpager2.widget.ViewPager2;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends AppCompatActivity {
    private ViewPager2 imageSliderViewPager;
    private LinearLayout layoutImageSliderDots;
    private ImageSliderAdapter imageSliderAdapter;
    private List<Integer> imageSliderImages;
    private Handler imageSliderHandler = new Handler(Looper.getMainLooper());
    private Runnable imageSliderRunnable;
    private RecyclerView recyclerViewCategories;
    private CategoryAdapter categoryAdapter;
    private List<CategoryItem> categoryList;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        imageSliderViewPager = findViewById(R.id.imageSliderViewPager);
        layoutImageSliderDots = findViewById(R.id.layoutImageSliderDots);
        recyclerViewCategories = findViewById(R.id.recyclerViewCategories);

        setupImageSlider();
        setupCategoryList();
    }

    private void setupImageSlider() {
        imageSliderImages = new ArrayList<>();
        imageSliderImages.add(R.drawable.slider_image1);
        imageSliderImages.add(R.drawable.slider_image2);
        imageSliderImages.add(R.drawable.slider_image3);
        imageSliderAdapter = new ImageSliderAdapter(imageSliderImages);
        imageSliderViewPager.setAdapter(imageSliderAdapter);
        imageSliderViewPager.setPageTransformer((page, position) -> {
            float scale = 0.92f + (1 - Math.abs(position)) * 0.08f;
            page.setScaleY(scale);
            page.setScaleX(scale);
            page.setAlpha(0.7f + (1 - Math.abs(position)) * 0.3f);
        });
        setupImageSliderDots();
        setCurrentImageSliderDot(0);
        imageSliderViewPager.registerOnPageChangeCallback(new ViewPager2.OnPageChangeCallback() {
            @Override
            public void onPageSelected(int position) {
                setCurrentImageSliderDot(position);
                imageSliderHandler.removeCallbacks(imageSliderRunnable);
                imageSliderHandler.postDelayed(imageSliderRunnable, 3000);
            }
        });
        imageSliderRunnable = new Runnable() {
            @Override
            public void run() {
                int nextItem = imageSliderViewPager.getCurrentItem() + 1;
                if (nextItem >= imageSliderAdapter.getItemCount()) {
                    nextItem = 0;
                }
                imageSliderViewPager.setCurrentItem(nextItem, true);
                imageSliderHandler.postDelayed(this, 3000);
            }
        };
        imageSliderHandler.postDelayed(imageSliderRunnable, 3000);
    }

    private void setupImageSliderDots() {
        int count = imageSliderImages.size();
        layoutImageSliderDots.removeAllViews();
        for (int i = 0; i < count; i++) {
            ImageView dot = new ImageView(this);
            int size = 16;
            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(size, size);
            params.setMargins(8, 0, 8, 0);
            dot.setLayoutParams(params);
            dot.setImageDrawable(ContextCompat.getDrawable(this, R.drawable.dot_inactive));
            layoutImageSliderDots.addView(dot);
        }
    }

    private void setCurrentImageSliderDot(int index) {
        int count = layoutImageSliderDots.getChildCount();
        for (int i = 0; i < count; i++) {
            ImageView dot = (ImageView) layoutImageSliderDots.getChildAt(i);
            if (i == index) {
                dot.setImageDrawable(ContextCompat.getDrawable(this, R.drawable.dot_active));
            } else {
                dot.setImageDrawable(ContextCompat.getDrawable(this, R.drawable.dot_inactive));
            }
        }
    }

    private void setupCategoryList() {
        categoryList = new ArrayList<>();
        categoryList.add(new CategoryItem(R.drawable.ic_launcher_foreground, "Burger"));
        categoryList.add(new CategoryItem(R.drawable.ic_launcher_foreground, "Fries"));
        categoryList.add(new CategoryItem(R.drawable.ic_launcher_foreground, "Pizza"));
        categoryList.add(new CategoryItem(R.drawable.ic_launcher_foreground, "Sushi"));
        categoryList.add(new CategoryItem(R.drawable.ic_launcher_foreground, "Salad"));
        categoryList.add(new CategoryItem(R.drawable.ic_launcher_foreground, "Drinks"));
        categoryAdapter = new CategoryAdapter(categoryList, item -> {
            Intent intent = new Intent(this, CategoryActivity.class);
            intent.putExtra("imageResId", item.getImageResId());
            intent.putExtra("name", item.getName());
            startActivity(intent);
        });
        LinearLayoutManager layoutManager = new LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false);
        recyclerViewCategories.setLayoutManager(layoutManager);
        recyclerViewCategories.setAdapter(categoryAdapter);
    }

    @Override
    protected void onPause() {
        super.onPause();
        imageSliderHandler.removeCallbacks(imageSliderRunnable);
    }

    @Override
    protected void onResume() {
        super.onResume();
        imageSliderHandler.postDelayed(imageSliderRunnable, 3000);
    }
}