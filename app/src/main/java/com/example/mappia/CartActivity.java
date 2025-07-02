package com.example.mappia;

import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

public class CartActivity extends AppCompatActivity {
    private RecyclerView recyclerViewCart;
    private TextView textTotalPrice;
    private Button buttonPlaceOrder;
    private CartAdapter cartAdapter;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_cart);

        recyclerViewCart = findViewById(R.id.recyclerViewCart);
        textTotalPrice = findViewById(R.id.textTotalPrice);
        buttonPlaceOrder = findViewById(R.id.buttonPlaceOrder);

        setupRecyclerView();
        updateTotalPrice();

        buttonPlaceOrder.setOnClickListener(v -> {
            Cart.getInstance().clear();
            // Navigate to OrderConfirmationActivity
            startActivity(new Intent(this, OrderConfirmationActivity.class));
            finish();
        });
    }

    private void setupRecyclerView() {
        cartAdapter = new CartAdapter(Cart.getInstance().getItems(), item -> {
            Cart.getInstance().removeItem(item);
            cartAdapter.updateCart(Cart.getInstance().getItems());
            updateTotalPrice();
        });
        recyclerViewCart.setLayoutManager(new LinearLayoutManager(this));
        recyclerViewCart.setAdapter(cartAdapter);
    }

    private void updateTotalPrice() {
        double total = Cart.getInstance().getTotalPrice();
        textTotalPrice.setText(String.format("Total: $%.2f", total));
    }
} 