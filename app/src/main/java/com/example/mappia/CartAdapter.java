package com.example.mappia;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class CartAdapter extends RecyclerView.Adapter<CartAdapter.CartViewHolder> {
    public interface OnRemoveFromCartListener {
        void onRemoveFromCart(FoodItem item);
    }

    private final List<Map.Entry<FoodItem, Integer>> cartEntries;
    private final OnRemoveFromCartListener listener;

    public CartAdapter(Map<FoodItem, Integer> cartItems, OnRemoveFromCartListener listener) {
        this.cartEntries = new ArrayList<>(cartItems.entrySet());
        this.listener = listener;
    }

    @NonNull
    @Override
    public CartViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext()).inflate(R.layout.item_cart, parent, false);
        return new CartViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull CartViewHolder holder, int position) {
        holder.bind(cartEntries.get(position));
    }

    @Override
    public int getItemCount() {
        return cartEntries.size();
    }

    public void updateCart(Map<FoodItem, Integer> cartItems) {
        cartEntries.clear();
        cartEntries.addAll(cartItems.entrySet());
        notifyDataSetChanged();
    }

    class CartViewHolder extends RecyclerView.ViewHolder {
        private final ImageView imageCartFood;
        private final TextView textCartFoodName;
        private final TextView textCartQuantity;
        private final TextView textCartFoodPrice;
        private final Button buttonRemoveFromCart;

        public CartViewHolder(@NonNull View itemView) {
            super(itemView);
            imageCartFood = itemView.findViewById(R.id.imageCartFood);
            textCartFoodName = itemView.findViewById(R.id.textCartFoodName);
            textCartQuantity = itemView.findViewById(R.id.textCartQuantity);
            textCartFoodPrice = itemView.findViewById(R.id.textCartFoodPrice);
            buttonRemoveFromCart = itemView.findViewById(R.id.buttonRemoveFromCart);
        }

        void bind(final Map.Entry<FoodItem, Integer> entry) {
            FoodItem item = entry.getKey();
            int quantity = entry.getValue();
            imageCartFood.setImageResource(item.getImageResId());
            textCartFoodName.setText(item.getName());
            textCartQuantity.setText("x" + quantity);
            textCartFoodPrice.setText(String.format("$%.2f", item.getPrice() * quantity));
            buttonRemoveFromCart.setOnClickListener(v -> listener.onRemoveFromCart(item));
        }
    }
} 