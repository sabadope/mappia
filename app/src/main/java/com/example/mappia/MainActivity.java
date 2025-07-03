package com.example.mappia;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import androidx.viewpager2.widget.ViewPager2;
import android.widget.LinearLayout;
import android.widget.ImageView;
import android.graphics.drawable.Drawable;
import androidx.core.content.ContextCompat;

import java.util.ArrayList;
import java.util.List;
import android.os.Handler;
import android.os.Looper;

public class MainActivity extends AppCompatActivity {
    private RecyclerView recyclerViewFood;
    private Button buttonViewCart;
    private FoodAdapter foodAdapter;
    private List<FoodItem> foodList;
    private ViewPager2 imageSliderViewPager;
    private LinearLayout layoutImageSliderDots;
    private ImageSliderAdapter imageSliderAdapter;
    private List<Integer> imageSliderImages;
    private Handler imageSliderHandler = new Handler(Looper.getMainLooper());
    private Runnable imageSliderRunnable;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        imageSliderViewPager = findViewById(R.id.imageSliderViewPager);
        layoutImageSliderDots = findViewById(R.id.layoutImageSliderDots);
        recyclerViewFood = findViewById(R.id.recyclerViewFood);
        buttonViewCart = findViewById(R.id.buttonViewCart);

        setupImageSlider();
        setupFoodList();
        setupRecyclerView();

        buttonViewCart.setOnClickListener(v -> {
            startActivity(new Intent(this, CartActivity.class));
        });
    }

    private void setupImageSlider() {
        imageSliderImages = new ArrayList<>();
        imageSliderImages.add(R.drawable.slider_image1);
        imageSliderImages.add(R.drawable.slider_image2);
        imageSliderImages.add(R.drawable.slider_image3);
        imageSliderAdapter = new ImageSliderAdapter(imageSliderImages);
        imageSliderViewPager.setAdapter(imageSliderAdapter);
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

    private void setupFoodList() {
        foodList = new ArrayList<>();
        foodList.add(new FoodItem(1, "Burger", R.drawable.ic_launcher_foreground, 5.99));
        foodList.add(new FoodItem(2, "Pizza", R.drawable.ic_launcher_background, 8.49));
        foodList.add(new FoodItem(3, "Sushi", R.drawable.ic_launcher_foreground, 12.99));
        foodList.add(new FoodItem(4, "Salad", R.drawable.ic_launcher_background, 6.49));
        foodList.add(new FoodItem(5, "Pasta", R.drawable.ic_launcher_foreground, 7.99));
    }

    private void setupRecyclerView() {
        foodAdapter = new FoodAdapter(foodList, item -> {
            Cart.getInstance().addItem(item);
            Toast.makeText(this, item.getName() + " added to cart!", Toast.LENGTH_SHORT).show();
        });
        recyclerViewFood.setLayoutManager(new LinearLayoutManager(this));
        recyclerViewFood.setAdapter(foodAdapter);
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