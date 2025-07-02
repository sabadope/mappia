package com.example.mappia;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.List;

public class MainActivity extends AppCompatActivity {
    private RecyclerView recyclerViewFood;
    private Button buttonViewCart;
    private FoodAdapter foodAdapter;
    private List<FoodItem> foodList;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        recyclerViewFood = findViewById(R.id.recyclerViewFood);
        buttonViewCart = findViewById(R.id.buttonViewCart);

        setupFoodList();
        setupRecyclerView();

        buttonViewCart.setOnClickListener(v -> {
            startActivity(new Intent(this, CartActivity.class));
        });
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
}